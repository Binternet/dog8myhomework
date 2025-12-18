# AWS Managed Policies for Terraform and Helm Deployment

Instead of creating custom policies, you can use AWS managed policies which are pre-configured and maintained by AWS. This is simpler and avoids policy size limitations.

## Required AWS Managed Policies

### Core Infrastructure Policies

1. **PowerUserAccess** (Recommended for development)
   - Policy ARN: `arn:aws:iam::aws:policy/PowerUserAccess`
   - Provides full access to AWS services and resources, except IAM user and group management
   - **Note**: This is a broad policy. For production, use more restrictive policies below.

### Alternative: Service-Specific Managed Policies

If we were on production environments (but we're not haha), we would use these more restrictive managed policies:

#### VPC & Networking
- **AmazonVPCFullAccess**
  - ARN: `arn:aws:iam::aws:policy/AmazonVPCFullAccess`
  - Full access to VPC operations

#### EKS
- **AmazonEKSClusterPolicy**
  - ARN: `arn:aws:iam::aws:policy/AmazonEKSClusterPolicy`
  - Required for EKS cluster operations
- **AmazonEKSWorkerNodePolicy**
  - ARN: `arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy`
  - Required for EKS node groups
- **AmazonEKS_CNI_Policy**
  - ARN: `arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy`
  - Required for EKS networking
- **AmazonEKSVPCResourceController**
  - ARN: `arn:aws:iam::aws:policy/AmazonEKSVPCResourceController`
  - Required for EKS VPC resource management

#### RDS
- **AmazonRDSFullAccess**
  - ARN: `arn:aws:iam::aws:policy/AmazonRDSFullAccess`
  - Full access to RDS operations

#### EC2
- **AmazonEC2FullAccess**
  - ARN: `arn:aws:iam::aws:policy/AmazonEC2FullAccess`
  - Full access to EC2 operations

#### Auto Scaling
- **AutoScalingFullAccess**
  - ARN: `arn:aws:iam::aws:policy/AutoScalingFullAccess`
  - Full access to Auto Scaling operations

#### CloudWatch Logs
- **CloudWatchLogsFullAccess**
  - ARN: `arn:aws:iam::aws:policy/CloudWatchLogsFullAccess`
  - Full access to CloudWatch Logs

#### ECR
- **AmazonEC2ContainerRegistryReadOnly**
  - ARN: `arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly`
  - Read-only access to ECR (for pulling images)
- **AmazonEC2ContainerRegistryPowerUser** (if you need to push images)
  - ARN: `arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser`
  - Full access to ECR repositories

#### IAM (Limited)
- **IAMFullAccess** (Use with caution - very powerful)
  - ARN: `arn:aws:iam::aws:policy/IAMFullAccess`
  - Full access to IAM
  - **Note**: For production, create a custom policy with only the IAM permissions needed (role creation, policy attachment, OIDC provider management)

## Quick Setup

### Option 1: PowerUserAccess (Simplest - Development Only)

```bash
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### Option 2: Service-Specific Policies (Recommended for Production, but Lo Relevanti!)

```bash
# Attach all required managed policies
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
aws iam attach-user-policy --user-name homework --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# For IAM, use a custom minimal policy (see iam-minimal-policy.json)
aws iam put-user-policy --user-name homework --policy-name IAMMinimalPolicy --policy-document file://policies/iam-minimal-policy.json
```

### Option 3: Attach to IAM Role

```bash
# Similar commands but use --role-name instead of --user-name
aws iam attach-role-policy --role-name <role-name> --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

## Verification

After attaching policies, verify access:

```bash
aws sts get-caller-identity
aws eks list-clusters --region us-east-1
aws ec2 describe-vpcs
```

## Security Best Practices

1. **Use IAM Roles instead of Users** when possible (e.g., for CI/CD)
2. **Use PowerUserAccess only for development** - it's too broad for production
3. **For production**, use service-specific policies and create minimal custom policies for IAM operations (forget about it...)
4. **Enable MFA** for IAM users with these permissions
5. **Use least privilege** - only attach policies you actually need
6. *Always Eat Pizza sideways*
