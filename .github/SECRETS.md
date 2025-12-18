# GitHub Actions Secrets Configuration

This document lists all required and optional secrets that need to be configured in GitHub Actions for the CI/CD workflow.

## Required Secrets

### AWS Credentials
These are **REQUIRED** for both build and deploy jobs:

- **`AWS_ACCESS_KEY_ID`** (Required)
  - Your AWS access key ID
  - Used for: ECR authentication, EKS cluster access, AWS API calls
  - Example: `AKIAIOSFODNN7EXAMPLE`

- **`AWS_SECRET_ACCESS_KEY`** (Required)
  - Your AWS secret access key
  - Used for: ECR authentication, EKS cluster access, AWS API calls
  - Example: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`

- **`AWS_REGION`** (Optional, defaults to `us-east-1`)
  - AWS region where your EKS cluster and ECR are located
  - Used for: ECR repository creation, EKS cluster configuration
  - Example: `eu-west-1`, `us-east-1`, `ap-southeast-1`

### Kubernetes Access
Choose **ONE** of the following options:

**Option 1: KUBECONFIG (Recommended for existing clusters)**
- **`KUBECONFIG`** (Optional, if using)
  - Base64-encoded kubeconfig file content
  - Used for: Direct Kubernetes cluster access
  - How to get: `cat ~/.kube/config | base64`
  - Note: If set, `EKS_CLUSTER_NAME` is not needed

**Option 2: EKS Cluster Name (Recommended for EKS)**
- **`EKS_CLUSTER_NAME`** (Optional, if using)
  - Name of your EKS cluster
  - Used for: Auto-configuring kubectl via `aws eks update-kubeconfig`
  - Example: `hello-world-cluster`
  - Note: Requires AWS credentials with EKS permissions

### Database Configuration

- **`RDS_PASSWORD`** (Required)
  - Password for the RDS MySQL database
  - Used for: Database connection authentication
  - Must be more than 8 characters
  - Example: `MySecurePassword123!`
  - Note: This will be stored as a Kubernetes secret

- **`RDS_INSTANCE_ID`** (Optional, defaults to `hello-world-mysql`)
  - RDS instance identifier to connect to
  - Used for: Finding the correct RDS instance
  - Example: `hello-world-mysql`
  - Note: If not set, the workflow will try to find an RDS instance with "hello-world" in the name

### Deployment Configuration

- **`NAMESPACE`** (Optional, defaults to `default`)
  - Kubernetes namespace where the application will be deployed
  - Used for: Helm deployment namespace
  - Example: `default`, `production`, `staging`

## Summary Table

| Secret Name | Required | Default | Description |
|------------|----------|---------|-------------|
| `AWS_ACCESS_KEY_ID` | ✅ Yes | - | AWS access key ID |
| `AWS_SECRET_ACCESS_KEY` | ✅ Yes | - | AWS secret access key |
| `AWS_REGION` | ⚠️ Optional | `us-east-1` | AWS region |
| `KUBECONFIG` | ⚠️ One of | - | Base64-encoded kubeconfig (Option 1) |
| `EKS_CLUSTER_NAME` | ⚠️ One of | - | EKS cluster name (Option 2) |
| `RDS_PASSWORD` | ✅ Yes | - | RDS MySQL database password |
| `RDS_INSTANCE_ID` | ⚠️ Optional | `hello-world-mysql` | RDS instance identifier |
| `NAMESPACE` | ⚠️ Optional | `default` | Kubernetes namespace |

## How to Set Secrets in GitHub

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with its name and value

## Environment Variables (Set in Workflow)

These are already configured in the workflow file and don't need to be set as secrets:

- `ECR_REPOSITORY`: `hello-world` (hardcoded)
- `IMAGE_NAME`: `hello-world` (hardcoded)

## Minimum Required Setup

For the workflow to work, you **MUST** set at minimum:

1. ✅ `AWS_ACCESS_KEY_ID`
2. ✅ `AWS_SECRET_ACCESS_KEY`
3. ✅ Either `KUBECONFIG` OR `EKS_CLUSTER_NAME`
4. ✅ `RDS_PASSWORD`

## Recommended Setup

For best results, set all of these:

1. ✅ `AWS_ACCESS_KEY_ID`
2. ✅ `AWS_SECRET_ACCESS_KEY`
3. ✅ `AWS_REGION` (e.g., `eu-west-1`)
4. ✅ `EKS_CLUSTER_NAME` (e.g., `hello-world-cluster`)
5. ✅ `RDS_PASSWORD` (your RDS MySQL password)
6. ⚠️ `RDS_INSTANCE_ID` (if your RDS instance has a different name)
7. ⚠️ `NAMESPACE` (if you want a specific namespace, otherwise defaults to `default`)

## IAM Permissions Required

The AWS credentials need permissions for:

- **ECR**: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`, `ecr:PutImage`, `ecr:CreateRepository`, `ecr:DescribeRepositories`
- **EKS**: `eks:DescribeCluster` (if using `EKS_CLUSTER_NAME`)
- **RDS**: `rds:DescribeDBInstances` (to get RDS connection details)
- **STS**: `sts:GetCallerIdentity` (to get AWS account ID)

## Example Secret Values

```bash
# AWS Credentials
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=eu-west-1

# Kubernetes (Option 1: KUBECONFIG)
KUBECONFIG=$(cat ~/.kube/config | base64)

# OR Kubernetes (Option 2: EKS Cluster Name)
EKS_CLUSTER_NAME=hello-world-cluster

# Database
RDS_PASSWORD=MySecurePassword123!
RDS_INSTANCE_ID=hello-world-mysql  # Optional, defaults to hello-world-mysql

# Deployment
NAMESPACE=default
```


