#!/bin/bash
# Builds the Docker image and pushes it to AWS ECR

# Script to build and push Docker image to ECR
# This script:
# 1. Gets AWS account ID and region
# 2. Creates ECR repository if it doesn't exist
# 3. Builds the Docker image
# 4. Tags and pushes the image to ECR

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Build and Push Docker Image to ECR${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Get AWS account ID and region
echo -e "${BLUE}Getting AWS account information...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS account ID. Please configure AWS credentials.${NC}"
    exit 1
fi

AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    # Try to get from Terraform outputs
    cd "$PROJECT_ROOT/terraform"
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"
fi

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not determine AWS region.${NC}"
    read -p "Enter AWS region (e.g., eu-west-1): " AWS_REGION
    if [ -z "$AWS_REGION" ]; then
        echo -e "${RED}Error: AWS region is required${NC}"
        exit 1
    fi
fi

ECR_REPO_NAME="${ECR_REPO_NAME:-hello-world}"
ECR_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo -e "${GREEN}✓ AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${GREEN}✓ AWS Region: $AWS_REGION${NC}"
echo -e "${GREEN}✓ ECR Repository: $ECR_REPO_URL${NC}"
echo -e "${GREEN}✓ Image Tag: $IMAGE_TAG${NC}"
echo ""

# Create ECR repository if it doesn't exist
echo -e "${BLUE}Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✓ ECR repository '$ECR_REPO_NAME' already exists${NC}"
else
    echo -e "${YELLOW}Creating ECR repository '$ECR_REPO_NAME'...${NC}"
    aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    echo -e "${GREEN}✓ ECR repository created${NC}"
fi
echo ""

# Login to ECR
echo -e "${BLUE}Logging in to ECR...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPO_URL" || {
    echo -e "${RED}Error: Failed to login to ECR${NC}"
    exit 1
}
echo -e "${GREEN}✓ Logged in to ECR${NC}"
echo ""

# Build the Docker image for linux/amd64 platform (EKS nodes are typically x86_64)
echo -e "${BLUE}Building Docker image for linux/amd64 platform...${NC}"
cd "$PROJECT_ROOT"

# Check if buildx is available and create a builder if needed
if ! docker buildx ls | grep -q "multiarch"; then
    echo -e "${YELLOW}Setting up Docker buildx for multi-platform builds...${NC}"
    docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch 2>/dev/null || true
fi

# Use buildx for cross-platform builds (required on ARM64/Apple Silicon)
docker buildx build \
    --platform linux/amd64 \
    --tag "${ECR_REPO_NAME}:${IMAGE_TAG}" \
    --load \
    .
echo -e "${GREEN}✓ Image built successfully${NC}"
echo ""

# Tag the image for ECR
echo -e "${BLUE}Tagging image for ECR...${NC}"
docker tag "${ECR_REPO_NAME}:${IMAGE_TAG}" "${ECR_REPO_URL}:${IMAGE_TAG}"
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

# Push the image to ECR
echo -e "${BLUE}Pushing image to ECR...${NC}"
docker push "${ECR_REPO_URL}:${IMAGE_TAG}"
echo -e "${GREEN}✓ Image pushed successfully${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Build and push complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Image location:${NC}"
echo -e "  ${YELLOW}$ECR_REPO_URL:$IMAGE_TAG${NC}"
echo ""
echo -e "${BLUE}To deploy this image, run:${NC}"
echo -e "  ${YELLOW}IMAGE_REPO=\"$ECR_REPO_URL\" IMAGE_TAG=\"$IMAGE_TAG\" make deploy${NC}"
echo ""

