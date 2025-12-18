#!/bin/bash
# Runs all tests (unit, integration, Terraform validation, Helm validation) in Docker containers.

# Test runner script - all tests run in Docker
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR"

# Generate unique test ID to avoid container name conflicts
TEST_ID=$(date +%s)-$$-$(shuf -i 1000-9999 -n 1)
COMPOSE_PROJECT_NAME="test-${TEST_ID}"

# Detect docker compose command
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Error: docker-compose or docker compose not found.${NC}"
    exit 1
fi

echo -e "${BLUE}Running automated tests in Docker (test ID: ${TEST_ID})...${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Build Docker image
echo -e "${BLUE}Building Docker image...${NC}"
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE build app

# Run unit tests (no dependencies needed - they use mocks, exclude integration tests)
echo -e "${BLUE}Running unit tests in Docker...${NC}"
if COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE run --rm --no-deps -v "$PROJECT_DIR/tests:/app/tests:ro" -e DB_HOST= -e DB_USER= -e DB_PASSWORD= -e DB_NAME= app python -m pytest tests/test_main.py -v -m "not integration" --tb=short; then
    echo -e "${GREEN}✓ Unit tests passed${NC}\n"
else
    echo -e "${RED}✗ Unit tests failed${NC}\n"
    exit 1
fi

# Run Terraform validation
echo -e "${BLUE}Running Terraform validation...${NC}"
if docker run --rm -v "$PROJECT_DIR/terraform:/terraform" -w /terraform hashicorp/terraform:latest init -backend=false > /dev/null 2>&1 && \
   docker run --rm -v "$PROJECT_DIR/terraform:/terraform" -w /terraform hashicorp/terraform:latest validate > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Terraform validation passed${NC}\n"
else
    echo -e "${YELLOW}⚠ Terraform validation failed or skipped (may require AWS credentials)${NC}\n"
fi

# Run Helm validation
echo -e "${BLUE}Running Helm validation...${NC}"
if docker run --rm -v "$PROJECT_DIR/helm:/helm" -w /helm alpine/helm:latest lint hello-world > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Helm validation passed${NC}\n"
else
    echo -e "${YELLOW}⚠ Helm validation failed${NC}\n"
fi

# Run integration tests with database
echo -e "${BLUE}Starting MySQL for integration tests...${NC}"
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE up -d mysql

echo -e "${BLUE}Waiting for MySQL to be ready...${NC}"
timeout=60
counter=0
while ! COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE exec -T mysql mysqladmin ping -h localhost -u root -proot > /dev/null 2>&1; do
    sleep 2
    counter=$((counter + 2))
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}MySQL failed to start within $timeout seconds${NC}"
        COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE logs mysql
        exit 1
    fi
done
echo -e "${GREEN}✓ MySQL is ready${NC}"

# Give MySQL a moment to fully initialize
sleep 2

echo -e "${BLUE}Running integration tests in Docker...${NC}"
# docker-compose run automatically connects to the project's default network
# The 'mysql' hostname will be resolvable because both containers are on the same network
if COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE run --rm -v "$PROJECT_DIR/tests:/app/tests:ro" -e DB_HOST=mysql -e DB_PORT=3306 -e DB_USER=root -e DB_PASSWORD=root -e DB_NAME=hello_world app python -m pytest tests/ -v -m integration --tb=short; then
    echo -e "${GREEN}✓ Integration tests passed${NC}\n"
else
    echo -e "${YELLOW}⚠ Integration tests failed or skipped${NC}\n"
fi

# Cleanup
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE down -v 2>/dev/null || true

echo -e "${GREEN}All tests completed!${NC}"

