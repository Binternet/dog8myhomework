#!/bin/bash
# Validates Terraform configuration files for syntax and formatting using Docker.

# Terraform validation script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

echo "Validating Terraform configuration..."

cd "$TERRAFORM_DIR"

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform not found${NC}"
    exit 1
fi

# Format check
echo "Checking Terraform formatting..."
if ! terraform fmt -check -recursive; then
    echo -e "${YELLOW}Warning: Some files need formatting. Run 'terraform fmt' to fix.${NC}"
fi

# Initialize
echo "Initializing Terraform..."
terraform init -backend=false > /dev/null 2>&1

# Validate
echo "Validating Terraform configuration..."
if terraform validate; then
    echo -e "${GREEN}✓ Terraform validation passed${NC}"
else
    echo -e "${RED}✗ Terraform validation failed${NC}"
    exit 1
fi

# Check for required files
echo "Checking required files..."
required_files=("main.tf" "variables.tf" "outputs.tf" "versions.tf")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ Required file missing: $file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ All Terraform validations passed${NC}"

