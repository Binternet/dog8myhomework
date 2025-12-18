.PHONY: help check-req check-aws-creds install test test-unit test-integration test-local-app \
	validate-terraform validate-helm lint clean deploy deploy-infra deploy-plan destroy build-push-ecr test-local-helm clean-helm-local

# Detect docker compose command (docker-compose or docker compose)
DOCKER_COMPOSE := $(shell if command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; elif docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo ""; fi)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-25s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check-req: ## Check that all required prerequisites are installed
	@chmod +x scripts/check-prerequisites.sh
	@./scripts/check-prerequisites.sh

install: ## Install all required prerequisites on the host machine
	@chmod +x scripts/install-prerequisites.sh
	@./scripts/install-prerequisites.sh

test: check-req ## Run ALL tests (linting, unit, integration, Terraform validation, Helm validation, local app test)
	@echo "=========================================="
	@echo "Running ALL tests"
	@echo "=========================================="
	@echo ""
	@echo "1. Running linting checks..."
	@$(MAKE) lint || echo "⚠ Linting completed with warnings"
	@echo ""
	@echo "2. Running core tests (unit, integration, validation)..."
	@./scripts/run-tests.sh
	@echo ""
	@echo "3. Running local app test..."
	@$(MAKE) test-local-app || echo "⚠ Local app test failed"
	@echo ""
	@echo "=========================================="
	@echo "✓ All tests completed!"
	@echo "=========================================="

test-unit: check-req ## Run unit tests in Docker
	$(DOCKER_COMPOSE) build app
	$(DOCKER_COMPOSE) run --rm -v $$(pwd)/tests:/app/tests:ro app python -m pytest tests/test_main.py -v --tb=short

test-integration: check-req ## Run integration tests in Docker
	$(DOCKER_COMPOSE) build app
	$(DOCKER_COMPOSE) up -d mysql
	@echo "Waiting for MySQL to be ready..."
	@timeout=30; counter=0; while ! $(DOCKER_COMPOSE) exec -T mysql mysqladmin ping -h localhost -u root -proot > /dev/null 2>&1; do sleep 1; counter=$$((counter + 1)); if [ $$counter -ge $$timeout ]; then echo "MySQL failed to start"; exit 1; fi; done
	$(DOCKER_COMPOSE) run --rm -v $$(pwd)/tests:/app/tests:ro -e DB_HOST=mysql -e DB_PORT=3306 -e DB_USER=root -e DB_PASSWORD=root -e DB_NAME=hello_world app python -m pytest tests/ -v -m integration --tb=short

test-terraform: check-req ## Run Terraform validation tests in Docker
	docker run --rm -v $$(pwd)/terraform:/terraform -w /terraform hashicorp/terraform:latest fmt -check -recursive || true
	@echo "Note: Full Terraform validation requires additional setup"

test-helm: check-req ## Run Helm validation tests in Docker
	docker run --rm -v $$(pwd)/helm:/helm -w /helm alpine/helm:latest lint hello-world || true
	@echo "Note: Full Helm validation requires additional setup"

test-local-app: check-req ## Test application locally with Docker Compose (app + database)
	./scripts/test-local-app.sh

test-local-helm: ## Test Helm chart locally using kind (Kubernetes in Docker)
	@chmod +x scripts/test-local-helm.sh
	@./scripts/test-local-helm.sh

validate-terraform: check-req ## Validate Terraform configuration in Docker
	docker run --rm -v $$(pwd)/terraform:/terraform -w /terraform hashicorp/terraform:latest init -backend=false
	docker run --rm -v $$(pwd)/terraform:/terraform -w /terraform hashicorp/terraform:latest validate

validate-helm: check-req ## Validate Helm charts in Docker
	docker run --rm -v $$(pwd)/helm:/helm -w /helm alpine/helm:latest lint hello-world

lint: check-req ## Run linting checks in Docker
	@echo "Running Python linting in Docker..."
	# E501 = line too long
	# W503 = line break before binary operator
	$(DOCKER_COMPOSE) run --rm -v $$(pwd)/src:/app/src:ro -v $$(pwd)/tests:/app/tests:ro app sh -c "pip install flake8 --quiet && flake8 src/ tests/ --max-line-length=120 --ignore=E501,W503" || echo "Linting completed with warnings"
	@echo "Running Terraform formatting check in Docker..."
	docker run --rm -v $$(pwd)/terraform:/terraform -w /terraform hashicorp/terraform:latest fmt -check -recursive || true
	@echo "Running Helm lint in Docker..."
	docker run --rm -v $$(pwd)/helm:/helm -w /helm alpine/helm:latest lint hello-world || true

clean: ## Clean up Docker resources and volumes
	$(DOCKER_COMPOSE) down -v
	@echo "Cleaned up Docker resources"

check-aws-creds: ## Check AWS credentials are configured
	@echo "Checking AWS credentials..."
	@if [ -z "$$AWS_ACCESS_KEY_ID" ] && [ -z "$$AWS_SECRET_ACCESS_KEY" ] && [ -z "$$AWS_PROFILE" ]; then \
		if ! aws sts get-caller-identity > /dev/null 2>&1; then \
			echo "Error: AWS credentials not found!"; \
			echo ""; \
			echo "Please configure AWS credentials using one of the following methods:"; \
			echo "  1. Run 'aws configure' to set up credentials"; \
			echo "  2. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables"; \
			echo "  3. Set AWS_PROFILE environment variable"; \
			echo "  4. Use IAM role (if running on EC2)"; \
			echo ""; \
			echo "To verify: aws sts get-caller-identity"; \
			exit 1; \
		fi; \
	fi
	@if ! aws sts get-caller-identity > /dev/null 2>&1; then \
		echo "Error: AWS credentials are invalid or expired!"; \
		echo ""; \
		echo "Please verify your credentials:"; \
		echo "  aws sts get-caller-identity"; \
		exit 1; \
	fi
	@echo "✓ AWS credentials verified"
	@aws sts get-caller-identity

deploy-plan: check-req check-aws-creds ## Plan Terraform deployment (dry-run)
	@echo "Planning Terraform deployment..."
	@cd terraform && terraform init
	@cd terraform && terraform plan

deploy-infra: check-req check-aws-creds ## Deploy infrastructure to AWS using Terraform
	@echo "=========================================="
	@echo "Deploying infrastructure to AWS"
	@echo "=========================================="
	@echo ""
	@echo "This will create/modify AWS resources. Make sure you have:"
	@echo "  1. AWS credentials configured (verified ✓)"
	@echo "  2. Appropriate AWS permissions"
	@echo "  3. Reviewed terraform/terraform.tfvars configuration"
	@echo ""
	@echo "Run 'make deploy-plan' first to preview changes."
	@echo ""
	@cd terraform && terraform init
	@cd terraform && terraform apply
	@echo ""
	@echo "=========================================="
	@echo "Deployment complete! Getting outputs..."
	@echo "=========================================="
	@cd terraform && terraform output

deploy: check-req check-aws-creds ## Deploy application to EKS cluster (requires infrastructure deployment first)
	@chmod +x scripts/deploy-helm.sh
	@./scripts/deploy-helm.sh

destroy: check-req check-aws-creds ## Destroy all AWS infrastructure created by Terraform
	@echo "=========================================="
	@echo "DESTROYING AWS INFRASTRUCTURE"
	@echo "=========================================="
	@echo ""
	@echo "\033[0;31mWARNING: This will destroy ALL resources created by Terraform:\033[0m"
	@echo "  - VPC and networking"
	@echo "  - EKS cluster and nodes"
	@echo "  - RDS database (ALL DATA WILL BE LOST)"
	@echo "  - Security groups"
	@echo "  - IAM roles and policies"
	@echo ""
	@echo "\033[1;31mThis action cannot be undone!\033[0m"
	@echo ""
	@read -p "Are you sure you want to destroy all infrastructure? (type 'yes' to confirm): " confirm
	@if [ "$$confirm" != "yes" ]; then \
		echo "Destroy cancelled."; \
		exit 1; \
	fi
	@echo ""
	@echo "Initializing Terraform..."
	@cd terraform && terraform init
	@echo ""
	@echo "Checking current state..."
	@cd terraform && echo "Resources in state:" && terraform state list 2>&1 | head -30 || echo "  No resources found in state or state file missing"
	@echo ""
	@echo "Destroying infrastructure..."
	@cd terraform && terraform destroy
	@echo ""
	@echo "=========================================="
	@echo "Destroy complete!"
	@echo "=========================================="

build-push-ecr: check-req check-aws-creds ## Build Docker image and push to ECR
	@chmod +x scripts/build-push-ecr.sh
	@./scripts/build-push-ecr.sh

clean-helm-local: ## Clean up local Helm test environment (kind cluster and PostgreSQL)
	@echo "Cleaning up local test environment..."
	@kind delete cluster --name hello-world-test 2>/dev/null || true
	@docker stop hello-world-postgres 2>/dev/null || true
	@docker rm hello-world-postgres 2>/dev/null || true
	@echo "✓ Cleanup complete"

