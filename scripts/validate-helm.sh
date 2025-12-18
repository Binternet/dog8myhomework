#!/bin/bash
# Validates Helm charts for syntax, structure, and best practices using Docker.

# Helm validation script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$SCRIPT_DIR/../helm/hello-world"

echo "Validating Helm chart..."

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm not found${NC}"
    exit 1
fi

# Lint
echo "Linting Helm chart..."
if helm lint "$HELM_DIR"; then
    echo -e "${GREEN}✓ Helm lint passed${NC}"
else
    echo -e "${RED}✗ Helm lint failed${NC}"
    exit 1
fi

# Template validation
echo "Validating Helm templates..."
if helm template test-release "$HELM_DIR" > /dev/null; then
    echo -e "${GREEN}✓ Helm template validation passed${NC}"
else
    echo -e "${RED}✗ Helm template validation failed${NC}"
    exit 1
fi

# Check required files
echo "Checking required files..."
required_files=("Chart.yaml" "values.yaml")
for file in "${required_files[@]}"; do
    if [ ! -f "$HELM_DIR/$file" ]; then
        echo -e "${RED}✗ Required file missing: $file${NC}"
        exit 1
    fi
done

required_templates=("deployment.yaml" "service.yaml" "secret.yaml")
for template in "${required_templates[@]}"; do
    if [ ! -f "$HELM_DIR/templates/$template" ]; then
        echo -e "${RED}✗ Required template missing: $template${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ All Helm validations passed${NC}"

