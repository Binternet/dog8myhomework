# Hello World Application

A simple Python application that displays "Hello World" with random facts from a database, deployed on AWS cloud infrastructure.

## Overview

This project is a complete example of a modern application deployment setup. It includes:

- **Application**: A Python program that shows "Hello World" with random facts
- **Database**: MySQL database to store the facts
- **Infrastructure**: Automated cloud setup on AWS (networking, servers, database)
- **Deployment**: Automated deployment to Kubernetes (container orchestration)
- **Testing**: Automated tests to ensure everything works correctly

The application runs in containers (Docker) and is managed by Kubernetes on Amazon's cloud platform (AWS EKS).

## Prerequisites

Before you can use this project, you need these tools installed on your computer:

| Tool | Purpose | How to Check |
|------|---------|--------------|
| **Docker** | Runs the application in containers | `docker --version` |
| **Docker Compose** | Manages multiple containers together | `docker compose version` |
| **Terraform** | Creates cloud infrastructure automatically | `terraform version` |
| **AWS CLI** | Connects to Amazon Web Services | `aws --version` |

### Quick Check

Run this command to check if everything is installed:

```bash
make check-req
```

If something is missing, you can install it automatically:

```bash
make install
```

### AWS Account Setup

You'll also need:
- An AWS account
- AWS credentials configured (run `aws configure`)
- Appropriate permissions to create cloud resources - see [aws-managed-policies.md](aws-managed-policies.md)

## Makefile Reference

The project uses a Makefile to simplify common tasks. Here are the most useful commands:

### Setup & Installation
- `make check-req` - Check if all required tools are installed
- `make install` - Automatically install missing prerequisites

### Testing
- `make test` - Run all tests (unit, integration, Terraform validation, Helm validation)
- `make test-local-app` - Test the application locally with Docker
- `make test-local-helm` - Test Kubernetes deployment locally

### Deployment
- `make deploy-plan` - Preview what will be created in AWS (dry-run)
- `make deploy-infra` - Create AWS infrastructure (VPC, EKS, database)
- `make build-push-ecr` - Build Docker image and push to ECR
- `make deploy` - Deploy the application to AWS EKS
- `make destroy` - Destroy all AWS infrastructure (WARNING: deletes everything)

### Utilities
- `make lint` - Check code quality
- `make clean` - Clean up local Docker resources
- `make help` - Show all available commands

## Deployment Flow

Here's the step-by-step process to deploy this application:

### Step 1: Check Prerequisites
```bash
make check-req
```
This verifies that Docker, Terraform, and AWS CLI are installed and working.

### Step 2: Configure AWS
```bash
aws configure
```
Enter your AWS access key, secret key, and region when prompted.

### Step 3: Configure Terraform Variables (Optional)
If you want to customize the deployment, create a `terraform/terraform.tfvars` file based on `terraform/terraform.tfvars.example`.

**Important**: The `rds_password` must be more than 8 characters long.

### Step 4: Plan Infrastructure Deployment
```bash
make deploy-plan
```
This shows what will be created in AWS without actually creating it (safe to run).

### Step 5: Deploy Infrastructure
```bash
make deploy-infra
```
This creates all the AWS resources:
- Virtual network (VPC)
- Kubernetes cluster (EKS)
- Database (RDS MySQL)
- Security groups and other necessary components

**Note**: This step takes 15-20 minutes and will create AWS resources that cost money.

Remember to destroy these resources! חראם על כל שקל!

### Step 6: Build and Push Docker Image
```bash
make build-push-ecr
```
This builds your Docker image and pushes it to AWS ECR (Elastic Container Registry). The image will be available for the Kubernetes cluster to pull.

**Note**: This step creates an ECR repository if it doesn't exist.

### Step 7: Deploy Application
```bash
make deploy
```
This deploys the application to the Kubernetes cluster created in Step 5 (infrastructure deployment). You'll be prompted for the database password.

**Important**: The database password must be more than 8 characters long.

**Note**: The cluster pulls the Docker image from ECR. Make sure you've run `make build-push-ecr` first, or the deployment will fail.

**Prerequisites**: Before running `make deploy`, you must have:
1. Deployed infrastructure with `make deploy-infra` (Step 5)
2. Built and pushed the Docker image with `make build-push-ecr` (Step 6)

### Step 8: Verify Deployment
The deployment script will show you the status of your application. You can also check manually:
```bash
kubectl get pods
kubectl logs -l app.kubernetes.io/name=hello-world
```

## Quick Start (Local Testing)

To test everything locally without deploying to AWS:

```bash
# Test the application with Docker
make test-local-app

# Test Kubernetes deployment locally
make test-local-helm
```

## Personal Recommendation 👌🏼

I recommend running this project on a fresh Ubuntu instance via Vagrant. This provides a clean, isolated environment that avoids conflicts with your local system and ensures consistent behavior across different machines.

To get started with Vagrant:
- Download Vagrant: [https://www.vagrantup.com/downloads](https://www.vagrantup.com/downloads)
- Use the local `Vagrantfile` in this project - just update the `synced_folder` value to point to your project directory

Once Vagrant is installed and the `Vagrantfile` is configured:
```bash
vagrant up
vagrant ssh
cd /vagrant_data
```

Using Vagrant helps ensure that all dependencies are properly isolated and the deployment process works consistently, especially when working with Docker, Kubernetes, and AWS CLI tools.

## Need Help?

- Run `make help` to see all available commands
- Check the scripts in the `scripts/` folder for detailed automation
- Praise the lord!
