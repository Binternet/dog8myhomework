#!/bin/bash
# Deploys the Helm chart to AWS EKS cluster by reading Terraform outputs, configuring kubectl, and deploying with RDS connection details.

# Script to deploy Helm chart to EKS cluster created by Terraform
# This script:
# 1. Gets Terraform outputs (EKS cluster name, RDS details)
# 2. Configures kubectl to connect to EKS
# 3. Creates Kubernetes secret for RDS password
# 4. Deploys Helm chart with RDS configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Record start time
DEPLOYMENT_START_TIME=$(date +%s)
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Helm Deployment to EKS${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment started at: $(date)${NC}"
echo ""

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo -e "${YELLOW}Install kubectl: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    echo -e "${YELLOW}Install Helm: https://helm.sh/docs/intro/install/${NC}"
    exit 1
fi

# Get Terraform outputs
echo -e "${BLUE}Getting Terraform outputs...${NC}"
cd "$PROJECT_ROOT/terraform"

# Check if Terraform has been initialized
if [ ! -d ".terraform" ]; then
    echo -e "${RED}Error: Terraform has not been initialized.${NC}"
    echo -e "${YELLOW}Please run 'make deploy-infra' first to create the infrastructure.${NC}"
    echo ""
    exit 1
fi

# Check if Terraform state file exists
if [ ! -f "terraform.tfstate" ] && [ ! -f "terraform.tfstate.backup" ]; then
    echo -e "${RED}Error: Terraform state file not found.${NC}"
    echo -e "${YELLOW}This means no infrastructure has been deployed yet.${NC}"
    echo ""
        echo -e "${YELLOW}Please run 'make deploy-infra' first to:${NC}"
    echo -e "  1. Create the AWS infrastructure (VPC, EKS, RDS)"
    echo -e "  2. Generate the Terraform state file"
    echo ""
    exit 1
fi

# Check if state file has any resources (optional but helpful)
if [ -f "terraform.tfstate" ]; then
    STATE_RESOURCES=$(terraform state list 2>/dev/null | wc -l || echo "0")
    if [ "$STATE_RESOURCES" -eq 0 ]; then
        echo -e "${YELLOW}Warning: Terraform state file exists but contains no resources.${NC}"
        echo -e "${YELLOW}This might mean the infrastructure was destroyed or never created.${NC}"
        echo ""
        echo -e "${YELLOW}Please run 'make deploy-infra' first to create the infrastructure.${NC}"
        echo ""
        exit 1
    fi
fi

# Get EKS cluster name
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
if [ -z "$EKS_CLUSTER_NAME" ]; then
    echo -e "${RED}Error: Could not get EKS cluster name from Terraform outputs${NC}"
    exit 1
fi

# Get RDS details first (we'll use this to extract region if needed)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_ADDRESS=$(terraform output -raw rds_address 2>/dev/null || echo "")
RDS_PORT=$(terraform output -raw rds_port 2>/dev/null || echo "3306")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "hello_world")
RDS_USERNAME=$(terraform output -raw rds_username 2>/dev/null || echo "")

if [ -z "$RDS_ENDPOINT" ] && [ -z "$RDS_ADDRESS" ]; then
    echo -e "${RED}Error: Could not get RDS endpoint from Terraform outputs${NC}"
    exit 1
fi

# Use RDS_ADDRESS if RDS_ENDPOINT is not available (RDS_ENDPOINT includes port)
if [ -n "$RDS_ENDPOINT" ]; then
    # Extract hostname from endpoint (endpoint format: hostname:port)
    RDS_HOST=$(echo "$RDS_ENDPOINT" | cut -d':' -f1)
else
    RDS_HOST="$RDS_ADDRESS"
fi

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    # Try to extract region from RDS hostname (format: hostname.identifier.region.rds.amazonaws.com)
    if [ -n "$RDS_HOST" ]; then
        # Extract region from RDS hostname (e.g., hello-world-mysql.c1i0gjwbsd9l.eu-west-1.rds.amazonaws.com -> eu-west-1)
        AWS_REGION=$(echo "$RDS_HOST" | sed -n 's/.*\.\([a-z0-9-]*\)\.rds\.amazonaws\.com/\1/p' || echo "")
    fi
    # Try to get from terraform.tfvars
    if [ -z "$AWS_REGION" ] && [ -f "terraform.tfvars" ]; then
        AWS_REGION=$(grep -E "^aws_region\s*=" terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1)
    fi
    # Try to get from AWS CLI configuration
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
    fi
    # Default fallback
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="us-east-1"
        echo -e "${YELLOW}Warning: Could not get AWS region from outputs, using default: $AWS_REGION${NC}"
    fi
fi

echo -e "${GREEN}✓ EKS Cluster: $EKS_CLUSTER_NAME${NC}"
echo -e "${GREEN}✓ AWS Region: $AWS_REGION${NC}"
echo -e "${GREEN}✓ RDS Host: $RDS_HOST${NC}"
echo -e "${GREEN}✓ RDS Port: $RDS_PORT${NC}"
echo -e "${GREEN}✓ RDS Database: $RDS_DATABASE${NC}"
echo -e "${GREEN}✓ RDS Username: $RDS_USERNAME${NC}"
echo ""

# Check AWS credentials before configuring kubectl
echo -e "${BLUE}Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials are invalid or expired${NC}"
    echo -e "${YELLOW}Please refresh your AWS credentials:${NC}"
    echo -e "  ${YELLOW}aws configure${NC}"
    echo -e "  ${YELLOW}Or if using temporary credentials, refresh your session${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS credentials valid${NC}"
echo ""

# Configure kubectl
echo -e "${BLUE}Configuring kubectl for EKS cluster...${NC}"
if ! aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" 2>&1; then
    echo ""
    echo -e "${RED}Error: Failed to configure kubectl${NC}"
    echo -e "${YELLOW}Possible causes:${NC}"
    echo -e "  1. AWS credentials expired - refresh with: ${YELLOW}aws configure${NC}"
    echo -e "  2. System clock out of sync - check system time"
    echo -e "  3. Insufficient permissions - verify IAM permissions"
    echo ""
    echo -e "${YELLOW}Try refreshing AWS credentials and run again:${NC}"
    echo -e "  ${YELLOW}aws configure${NC}"
    echo -e "  ${YELLOW}make deploy${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Verify cluster connection
echo -e "${BLUE}Verifying cluster connection...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

# Get RDS password
echo -e "${YELLOW}Enter RDS password (must be more than 8 characters, or press Enter to use existing secret):${NC}"
read -s RDS_PASSWORD

# Set namespace (default to 'default')
NAMESPACE="${NAMESPACE:-default}"

# Flag to track if we should use existing secret
USE_EXISTING_SECRET=false

# Create namespace if it doesn't exist
echo -e "${BLUE}Creating namespace '$NAMESPACE' if it doesn't exist...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# Create or update secret for RDS password
if [ -n "$RDS_PASSWORD" ]; then
    echo -e "${BLUE}Creating Kubernetes secret for RDS password...${NC}"
    # Check if secret already exists
    if kubectl get secret hello-world-db-secret -n "$NAMESPACE" &>/dev/null; then
        # Update existing secret
        kubectl create secret generic hello-world-db-secret \
            --from-literal=password="$RDS_PASSWORD" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo -e "${GREEN}✓ Secret updated${NC}"
    else
        # Create new secret with Helm labels/annotations so Helm can manage it
        kubectl create secret generic hello-world-db-secret \
            --from-literal=password="$RDS_PASSWORD" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | \
        kubectl label --local -f - \
            app.kubernetes.io/managed-by=Helm \
            -o yaml | \
        kubectl annotate --local -f - \
            meta.helm.sh/release-name=hello-world \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            -o yaml | kubectl apply -f -
        echo -e "${GREEN}✓ Secret created${NC}"
    fi
    echo ""
elif kubectl get secret hello-world-db-secret -n "$NAMESPACE" &>/dev/null; then
    # Secret exists and user wants to use it - ensure it has Helm labels/annotations
    echo -e "${BLUE}Using existing secret 'hello-world-db-secret' (password unchanged)...${NC}"
    # Add Helm labels/annotations if missing (non-destructive)
    kubectl label secret hello-world-db-secret -n "$NAMESPACE" \
        app.kubernetes.io/managed-by=Helm \
        --overwrite &>/dev/null || true
    kubectl annotate secret hello-world-db-secret -n "$NAMESPACE" \
        meta.helm.sh/release-name=hello-world \
        meta.helm.sh/release-namespace="$NAMESPACE" \
        --overwrite &>/dev/null || true
    echo -e "${GREEN}✓ Using existing secret (password preserved)${NC}"
    echo ""
    # Set flag to use existing secret
    USE_EXISTING_SECRET=true
else
    # No password provided and secret doesn't exist - error
    echo -e "${RED}Error: No RDS password provided and secret 'hello-world-db-secret' does not exist${NC}"
    echo -e "${YELLOW}Please provide the RDS password (must be more than 8 characters)${NC}"
    exit 1
fi

# Get image repository and tag
echo -e "${BLUE}Configuring Docker image...${NC}"

# Try to get ECR repository URL from AWS account
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
ECR_REPO_NAME="${ECR_REPO_NAME:-hello-world}"

if [ -n "$AWS_ACCOUNT_ID" ] && [ -n "$AWS_REGION" ]; then
    ECR_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
    
    # Check if ECR repository exists
    if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo -e "${GREEN}✓ Found ECR repository: $ECR_REPO_URL${NC}"
        IMAGE_REPO="${IMAGE_REPO:-$ECR_REPO_URL}"
    else
        echo -e "${YELLOW}⚠ ECR repository '$ECR_REPO_NAME' not found in region $AWS_REGION${NC}"
        echo -e "${YELLOW}  You can create it with:${NC}"
        echo -e "${YELLOW}    aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION${NC}"
        echo ""
        echo -e "${YELLOW}Enter Docker image repository (e.g., $ECR_REPO_URL or ghcr.io/username/repo):${NC}"
        read -p "Image repository [default: $ECR_REPO_URL]: " USER_IMAGE_REPO
        IMAGE_REPO="${USER_IMAGE_REPO:-$ECR_REPO_URL}"
    fi
else
    echo -e "${YELLOW}Enter Docker image repository (e.g., ${AWS_ACCOUNT_ID:-ACCOUNT}.dkr.ecr.${AWS_REGION:-REGION}.amazonaws.com/hello-world):${NC}"
    read -p "Image repository: " USER_IMAGE_REPO
    if [ -z "$USER_IMAGE_REPO" ]; then
        echo -e "${RED}Error: Image repository is required${NC}"
        echo -e "${YELLOW}You need to build and push your Docker image first.${NC}"
        echo -e "${YELLOW}Example:${NC}"
        echo -e "  1. Build: docker build -t hello-world:latest ."
        echo -e "  2. Tag: docker tag hello-world:latest $ECR_REPO_URL:latest"
        echo -e "  3. Push: aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URL"
        echo -e "  4. Push: docker push $ECR_REPO_URL:latest"
        exit 1
    fi
    IMAGE_REPO="$USER_IMAGE_REPO"
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
if [ -z "$IMAGE_TAG" ] || [ "$IMAGE_TAG" = "prompt" ]; then
    read -p "Image tag [default: latest]: " USER_IMAGE_TAG
    IMAGE_TAG="${USER_IMAGE_TAG:-latest}"
fi

echo -e "${BLUE}Deploying Helm chart...${NC}"
echo -e "${YELLOW}Image: $IMAGE_REPO:$IMAGE_TAG${NC}"
echo ""

# Check if image is from ECR and set up imagePullSecrets if needed
IMAGE_PULL_SECRETS_ARGS=""
if echo "$IMAGE_REPO" | grep -q "\.dkr\.ecr\."; then
    echo -e "${BLUE}Image is from ECR, setting up image pull secret...${NC}"
    SECRET_NAME="ecr-registry-secret"
    
    # Check if secret already exists
    if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}Creating ECR image pull secret...${NC}"
        # Get ECR login token
        ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null || echo "")
        if [ -n "$ECR_TOKEN" ]; then
            ECR_REGISTRY=$(echo "$IMAGE_REPO" | cut -d'/' -f1)
            kubectl create secret docker-registry "$SECRET_NAME" \
                --docker-server="$ECR_REGISTRY" \
                --docker-username=AWS \
                --docker-password="$ECR_TOKEN" \
                --namespace="$NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            echo -e "${GREEN}✓ ECR image pull secret created${NC}"
        else
            echo -e "${YELLOW}⚠ Could not get ECR token. You may need to create image pull secret manually.${NC}"
        fi
    else
        echo -e "${GREEN}✓ ECR image pull secret already exists${NC}"
    fi
    # Set imagePullSecrets in Helm values
    IMAGE_PULL_SECRETS_ARGS="--set imagePullSecrets[0].name=$SECRET_NAME"
    echo ""
fi

# Verify image exists if using ECR
if echo "$IMAGE_REPO" | grep -q "\.dkr\.ecr\."; then
    echo -e "${BLUE}Verifying image exists in ECR...${NC}"
    ECR_REPO_NAME=$(echo "$IMAGE_REPO" | cut -d'/' -f2)
    ECR_REGISTRY=$(echo "$IMAGE_REPO" | cut -d'/' -f1)
    
    if aws ecr describe-images --repository-name "$ECR_REPO_NAME" --image-ids imageTag="$IMAGE_TAG" --region "$AWS_REGION" &>/dev/null; then
        echo -e "${GREEN}✓ Image $IMAGE_REPO:$IMAGE_TAG exists in ECR${NC}"
    else
        echo -e "${YELLOW}⚠ Image $IMAGE_REPO:$IMAGE_TAG not found in ECR${NC}"
        echo -e "${YELLOW}  Available tags:${NC}"
        aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION" --query 'imageIds[*].imageTag' --output table 2>/dev/null || echo "  Could not list images"
        echo ""
        echo -e "${YELLOW}You may need to build and push the image first:${NC}"
        echo -e "${YELLOW}  make build-push-ecr${NC}"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Deployment cancelled. Run 'make build-push-ecr' first.${NC}"
            exit 1
        fi
    fi
    echo ""
fi

# Verify secret exists if we're using existingSecret
if [ -n "$RDS_PASSWORD" ] || [ "$USE_EXISTING_SECRET" = "true" ]; then
    echo -e "${BLUE}Verifying secret 'hello-world-db-secret' exists...${NC}"
    if ! kubectl get secret hello-world-db-secret -n "$NAMESPACE" &>/dev/null; then
        echo -e "${RED}Error: Secret 'hello-world-db-secret' not found in namespace '$NAMESPACE'${NC}"
        echo -e "${YELLOW}Please create the secret first or provide a password${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Secret 'hello-world-db-secret' exists${NC}"
    echo ""
fi

# Deploy with Helm
echo -e "${BLUE}Deploying Helm chart...${NC}"
set +e  # Temporarily disable exit on error to handle timeout gracefully
#set -x # Debugging
helm upgrade --install hello-world "$PROJECT_ROOT/helm/hello-world" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set image.repository="$IMAGE_REPO" \
    --set image.tag="$IMAGE_TAG" \
    --set database.host="$RDS_HOST" \
    --set database.port="$RDS_PORT" \
    --set database.name="$RDS_DATABASE" \
    --set database.username="$RDS_USERNAME" \
    $([ -n "$RDS_PASSWORD" ] || [ "$USE_EXISTING_SECRET" = "true" ] && echo "--set database.existingSecret=hello-world-db-secret" || echo "") \
    $IMAGE_PULL_SECRETS_ARGS \
    --wait \
    --timeout 3m

HELM_EXIT_CODE=$?
set -e  # Re-enable exit on error

# Calculate deployment duration
DEPLOYMENT_END_TIME=$(date +%s)
DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
DEPLOYMENT_MINUTES=$((DEPLOYMENT_DURATION / 60))
DEPLOYMENT_SECONDS=$((DEPLOYMENT_DURATION % 60))

if [ $HELM_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment completed at: $(date)${NC}"
    if [ $DEPLOYMENT_MINUTES -gt 0 ]; then
        echo -e "${GREEN}Total deployment time: ${DEPLOYMENT_MINUTES}m ${DEPLOYMENT_SECONDS}s (${DEPLOYMENT_DURATION} seconds)${NC}"
    else
        echo -e "${GREEN}Total deployment time: ${DEPLOYMENT_DURATION} seconds${NC}"
    fi
    echo ""
    
    # Rollout restart to ensure pods use the new image
    echo -e "${BLUE}Rolling out new deployment to ensure pods use the latest image...${NC}"
    DEPLOYMENT_NAME=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=hello-world -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$DEPLOYMENT_NAME" ]; then
        kubectl rollout restart deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"
        echo -e "${GREEN}✓ Rollout restart initiated${NC}"
        echo -e "${BLUE}Waiting for rollout to complete...${NC}"
        kubectl rollout status deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout=3m
        echo ""
    else
        echo -e "${YELLOW}⚠ Could not find deployment to restart${NC}"
    fi
    
    echo -e "${BLUE}Checking deployment status...${NC}"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=hello-world
    echo ""
    
    # Get service information
    SERVICE_NAME=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=hello-world -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    SERVICE_TYPE=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.spec.type}' 2>/dev/null || echo "ClusterIP")
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Access the Application${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
        # Wait for LoadBalancer to get an external IP
        echo -e "${YELLOW}Waiting for LoadBalancer to get an external IP...${NC}"
        EXTERNAL_IP=""
        for i in {1..30}; do
            EXTERNAL_IP=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                         kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -n "$EXTERNAL_IP" ]; then
                break
            fi
            sleep 2
        done
        
        if [ -n "$EXTERNAL_IP" ]; then
            PORT=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
            echo -e "${GREEN}✓ Application is available at:${NC}"
            echo -e "  ${YELLOW}http://${EXTERNAL_IP}:${PORT}${NC}"
            echo ""
            echo -e "${BLUE}Test the endpoint:${NC}"
            echo -e "  ${YELLOW}curl http://${EXTERNAL_IP}:${PORT}${NC}"
        else
            echo -e "${YELLOW}LoadBalancer is still provisioning. Check status with:${NC}"
            echo -e "  kubectl get svc -n $NAMESPACE $SERVICE_NAME"
        fi
    else
        # ClusterIP service - use port-forward
        PORT=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
        
        # Get EKS cluster endpoint
        EKS_ENDPOINT=""
        if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
            EKS_ENDPOINT=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw eks_cluster_endpoint 2>/dev/null || echo "")
        fi
        if [ -z "$EKS_ENDPOINT" ]; then
            # Try to get from kubectl cluster-info
            EKS_ENDPOINT=$(kubectl cluster-info 2>/dev/null | grep -oP 'https://[^\s]+' | head -1 || echo "")
        fi
        
        echo -e "${BLUE}Service type: ClusterIP (internal only)${NC}"
        echo ""
        
        if [ -n "$EKS_ENDPOINT" ]; then
            echo -e "${GREEN}EKS Cluster Endpoint:${NC}"
            echo -e "  ${YELLOW}${EKS_ENDPOINT}${NC}"
            echo ""
        fi
        
        echo -e "${GREEN}To access the application, use port-forward:${NC}"
        echo -e "  ${YELLOW}kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8080:${PORT}${NC}"
        echo ""
        echo -e "${BLUE}Then access the application at:${NC}"
        echo -e "  ${YELLOW}http://localhost:8080${NC}"
        echo ""
        echo -e "${BLUE}Or test directly with:${NC}"
        echo -e "  ${YELLOW}kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8080:${PORT} &${NC}"
        echo -e "  ${YELLOW}curl http://localhost:8080${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Useful Commands${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}View logs:${NC}"
    echo -e "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=hello-world --tail=50"
    echo ""
    echo -e "${BLUE}View service details:${NC}"
    echo -e "  kubectl get svc -n $NAMESPACE $SERVICE_NAME"
    echo ""
    echo -e "${BLUE}Delete deployment:${NC}"
    echo -e "  helm uninstall hello-world -n $NAMESPACE"
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Deployment failed or timed out${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Deployment ended at: $(date)${NC}"
    if [ $DEPLOYMENT_MINUTES -gt 0 ]; then
        echo -e "${RED}Total deployment time: ${DEPLOYMENT_MINUTES}m ${DEPLOYMENT_SECONDS}s (${DEPLOYMENT_DURATION} seconds)${NC}"
    else
        echo -e "${RED}Total deployment time: ${DEPLOYMENT_DURATION} seconds${NC}"
    fi
    echo ""
    echo -e "${BLUE}Debugging information:${NC}"
    echo ""
    
    # Check Helm release status
    echo -e "${YELLOW}Helm release status:${NC}"
    helm status hello-world -n "$NAMESPACE" 2>/dev/null || echo "  Release not found or failed"
    echo ""
    
    # Check pods
    echo -e "${YELLOW}Pod status:${NC}"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=hello-world || echo "  No pods found"
    echo ""
    
    # Check pod events
    echo -e "${YELLOW}Recent pod events:${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | grep hello-world | tail -10 || echo "  No events found"
    echo ""
    
    # Try to get pod logs if any pod exists
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=hello-world -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo -e "${YELLOW}Pod logs for $POD_NAME:${NC}"
        kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=50 || echo "  Could not retrieve logs"
        echo ""
        echo -e "${YELLOW}Pod description for $POD_NAME:${NC}"
        kubectl describe pod -n "$NAMESPACE" "$POD_NAME" | tail -30 || echo "  Could not describe pod"
    else
        echo -e "${YELLOW}No pods found to inspect${NC}"
    fi
    echo ""
    
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo -e "  1. Check if the image exists: ${BLUE}aws ecr describe-images --repository-name hello-world --region $AWS_REGION${NC}"
    echo -e "  2. Verify image pull secret: ${BLUE}kubectl get secret ecr-registry-secret -n $NAMESPACE${NC}"
    echo -e "  3. Check RDS connectivity from cluster nodes"
    echo -e "  4. View all events: ${BLUE}kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'${NC}"
    echo ""
    
    exit 1
fi

