#!/bin/bash
# Tests the Helm chart locally using kind (Kubernetes in Docker), sets up MySQL, builds the image, and deploys the chart.

# Script to test Helm chart locally using kind (Kubernetes in Docker)
# This script:
# 1. Checks for kind installation
# 2. Creates a local Kubernetes cluster
# 3. Sets up a local MySQL database
# 4. Builds and loads the Docker image
# 5. Deploys the Helm chart
# 6. Tests the deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="hello-world-test"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Local Helm Chart Testing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    echo -e "${YELLOW}Install Helm: https://helm.sh/docs/intro/install/${NC}"
    exit 1
fi

# Check for kind
if ! command -v kind &> /dev/null || (command -v kind &> /dev/null && ! kind version &> /dev/null); then
    # Check if kind exists but can't execute (wrong architecture)
    if command -v kind &> /dev/null && ! kind version &> /dev/null; then
        echo -e "${YELLOW}kind binary exists but cannot execute (wrong architecture). Removing...${NC}"
        sudo rm -f /usr/local/bin/kind 2>/dev/null || rm -f ~/.local/bin/kind 2>/dev/null || true
    fi
    
    echo -e "${YELLOW}kind is not installed or wrong architecture. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install kind
        else
            echo -e "${RED}Please install Homebrew first, or install kind manually:${NC}"
            echo -e "  https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Detect architecture
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                KIND_ARCH="amd64"
                ;;
            aarch64|arm64)
                KIND_ARCH="arm64"
                ;;
            *)
                echo -e "${YELLOW}Unsupported architecture: $ARCH. Please install kind manually.${NC}"
                echo -e "  https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
                exit 1
                ;;
        esac
        echo -e "${BLUE}Detected architecture: $ARCH, using $KIND_ARCH${NC}"
        curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-${KIND_ARCH}"
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
        echo -e "${GREEN}✓ kind installed${NC}"
    else
        echo -e "${RED}Unsupported OS. Please install kind manually:${NC}"
        echo -e "  https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
else
    KIND_VERSION=$(kind version 2>&1 | grep -oE 'kind v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/kind v//' || echo "unknown")
    echo -e "${GREEN}✓ kind is already installed (version: $KIND_VERSION)${NC}"
fi

# Verify kind is working
if ! kind version &> /dev/null; then
    echo -e "${RED}Error: kind is installed but cannot execute. Please check architecture compatibility.${NC}"
    exit 1
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Cluster '$CLUSTER_NAME' already exists.${NC}"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Deleting existing cluster...${NC}"
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo -e "${YELLOW}Using existing cluster${NC}"
    fi
fi

# Create cluster if it doesn't exist
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${BLUE}Creating kind cluster...${NC}"
    kind create cluster --name "$CLUSTER_NAME" --wait 5m
    echo -e "${GREEN}✓ Cluster created${NC}"
else
    echo -e "${GREEN}✓ Using existing cluster${NC}"
fi

# Configure kubectl
export KUBECONFIG="$(kind get kubeconfig-path --name="$CLUSTER_NAME")"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo ""
echo -e "${BLUE}Building Docker image...${NC}"
cd "$PROJECT_ROOT"
docker build -t hello-world:local .

echo -e "${BLUE}Loading image into kind cluster...${NC}"
kind load docker-image hello-world:local --name "$CLUSTER_NAME"
echo -e "${GREEN}✓ Image loaded${NC}"

echo ""
echo -e "${BLUE}Setting up local MySQL database...${NC}"

# Check if MySQL container is already running
if docker ps -a | grep -q "hello-world-mysql"; then
    if docker ps | grep -q "hello-world-mysql"; then
        echo -e "${YELLOW}MySQL container already running${NC}"
    else
        echo -e "${BLUE}Starting existing MySQL container...${NC}"
        docker start hello-world-mysql
    fi
else
    echo -e "${BLUE}Starting MySQL container...${NC}"
    # Get kind network name
    KIND_NETWORK=$(docker network ls | grep kind | awk '{print $2}' | head -1)
    if [ -z "$KIND_NETWORK" ]; then
        KIND_NETWORK="kind"
    fi
    
    docker run -d \
        --name hello-world-mysql \
        -e MYSQL_ROOT_PASSWORD=root \
        -e MYSQL_DATABASE=hello_world \
        -p 3306:3306 \
        --network "$KIND_NETWORK" \
        mysql:8.0
    
    echo -e "${BLUE}Waiting for MySQL to be ready...${NC}"
    sleep 5
    for i in {1..30}; do
        if docker exec hello-world-mysql mysqladmin ping -h localhost -u root -proot &> /dev/null; then
            echo -e "${GREEN}✓ MySQL is ready${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ MySQL failed to start${NC}"
            exit 1
        fi
        sleep 1
    done
fi

# Get MySQL IP in kind network
MYSQL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hello-world-mysql)
if [ -z "$MYSQL_IP" ]; then
    # Try alternative method
    MYSQL_IP=$(docker inspect hello-world-mysql | grep -oP '"IPAddress": "\K[^"]+' | head -1)
fi

if [ -z "$MYSQL_IP" ]; then
    echo -e "${YELLOW}Warning: Could not get MySQL IP, using host.docker.internal${NC}"
    MYSQL_IP="host.docker.internal"
else
    echo -e "${GREEN}✓ MySQL IP: $MYSQL_IP${NC}"
fi

# Populate database with facts (optional)
echo -e "${BLUE}Populating database with sample data...${NC}"
sleep 2
docker exec -i hello-world-mysql mysql -u root -proot hello_world <<EOF || true
CREATE TABLE IF NOT EXISTS random_facts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    fact TEXT NOT NULL
);

INSERT INTO random_facts (fact) VALUES
    ('The first computer bug was an actual bug - a moth found in a Harvard Mark II computer in 1947.'),
    ('Honey never spoils. Archaeologists have found 3000-year-old honey in Egyptian tombs that is still edible.'),
    ('Octopuses have three hearts.'),
    ('A group of flamingos is called a flamboyance.'),
    ('Bananas are berries, but strawberries are not.');
EOF

echo ""
echo -e "${BLUE}Creating Kubernetes secret for database password...${NC}"
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic hello-world-db-secret \
    --from-literal=password=root \
    --namespace=default \
    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Secret created${NC}"

echo ""
echo -e "${BLUE}Deploying Helm chart...${NC}"
helm upgrade --install hello-world "$PROJECT_ROOT/helm/hello-world" \
    --namespace default \
    --create-namespace \
    --set image.repository=hello-world \
    --set image.tag=local \
    --set image.pullPolicy=Never \
    --set database.host="$MYSQL_IP" \
    --set database.port=3306 \
    --set database.name=hello_world \
    --set database.username=root \
    --set database.existingSecret=hello-world-db-secret \
    --wait \
    --timeout 5m

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Checking deployment status...${NC}"
    kubectl get pods -l app.kubernetes.io/name=hello-world
    echo ""
    
    # Wait for pod to be ready and running
    echo -e "${BLUE}Waiting for pod to be ready...${NC}"
    for i in {1..30}; do
        POD_STATUS=$(kubectl get pods -l app.kubernetes.io/name=hello-world -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
        if [ "$POD_STATUS" == "Running" ]; then
            echo -e "${GREEN}✓ Pod is running${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠ Pod not in Running state yet, showing logs anyway${NC}"
        fi
        sleep 1
    done
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Application Logs${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Get pod name for more reliable log access
    POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=hello-world -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$POD_NAME" ]; then
        echo -e "${BLUE}Pod: $POD_NAME${NC}"
        echo ""
        kubectl logs "$POD_NAME" --tail=100 || kubectl logs -l app.kubernetes.io/name=hello-world --tail=100 || true
    else
        kubectl logs -l app.kubernetes.io/name=hello-world --tail=100 || true
    fi
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}Useful commands:${NC}"
    echo -e "  ${YELLOW}View logs (follow):${NC}"
    echo -e "    kubectl logs -l app.kubernetes.io/name=hello-world -f"
    echo ""
    echo -e "  ${YELLOW}View pod details:${NC}"
    echo -e "    kubectl describe pod -l app.kubernetes.io/name=hello-world"
    echo ""
    echo -e "  ${YELLOW}Delete test cluster:${NC}"
    echo -e "    kind delete cluster --name $CLUSTER_NAME"
    echo ""
    echo -e "  ${YELLOW}Stop MySQL:${NC}"
    echo -e "    docker stop hello-world-mysql && docker rm hello-world-mysql"
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Deployment failed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${BLUE}Checking pod status...${NC}"
    kubectl get pods -l app.kubernetes.io/name=hello-world || true
    echo ""
    echo -e "${BLUE}Pod description:${NC}"
    kubectl describe pod -l app.kubernetes.io/name=hello-world || true
    echo ""
    echo -e "${BLUE}Pod logs (if available):${NC}"
    kubectl logs -l app.kubernetes.io/name=hello-world --tail=50 || true
    exit 1
fi

