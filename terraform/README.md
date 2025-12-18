# Terraform Infrastructure for Hello World Application

This Terraform configuration provisions AWS infrastructure including VPC, networking, and EKS cluster for the hello-world application.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl installed
- AWS IAM permissions for creating VPC, EKS, and related resources

## Structure

- `versions.tf` - Terraform and provider version constraints
- `variables.tf` - Input variables
- `main.tf` - Main infrastructure resources
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example variable values

## Quick Start

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review the execution plan:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

6. Configure kubectl:
   ```bash
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```
   Or use the output command:
   ```bash
   $(terraform output -raw configure_kubectl)
   ```

## Infrastructure Components

### VPC
- VPC with configurable CIDR block
- DNS hostnames and DNS support enabled

### Networking
- Public subnets (one per availability zone)
- Private subnets (one per availability zone)
- Internet Gateway for public subnet internet access
- NAT Gateway(s) for private subnet internet access (optional)
- Route tables and associations

### EKS Cluster
- Managed Kubernetes cluster
- Cluster logging enabled (API, audit, authenticator, controller manager, scheduler)
- OIDC provider for IAM integration
- Security groups for cluster and nodes

### EKS Node Group
- Managed node group with configurable instance types
- Auto-scaling configuration
- Deployed in private subnets

## Variables

Key variables (see `variables.tf` for full list):

- `aws_region` - AWS region (default: us-east-1)
- `project_name` - Project name for resource naming
- `vpc_cidr` - VPC CIDR block (default: 10.0.0.0/16)
- `eks_cluster_version` - Kubernetes version (default: 1.28)
- `eks_node_instance_types` - EC2 instance types for nodes
- `eks_node_desired_size` - Desired number of nodes

## Outputs

Important outputs:

- `eks_cluster_name` - EKS cluster name
- `eks_cluster_endpoint` - Cluster API endpoint
- `eks_cluster_certificate_authority_data` - CA certificate data
- `configure_kubectl` - Command to configure kubectl

## Remote State (Optional)

To use remote state with S3, uncomment and configure the backend in `versions.tf`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "hello-world/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

## Cost Considerations

- NAT Gateways incur hourly charges (~$0.045/hour each, wallak mamash yakar!!)
- EKS cluster costs ~$0.10/hour (gam lo zol...)
- EC2 instances for node groups are charged per instance type
- Consider using `enable_nat_gateway = false` for development environments
- How do we say? what was was, was was.

## Security Notes

- EKS nodes are deployed in private subnets
- Security groups restrict traffic appropriately
- Consider adding additional security group rules based on your requirements
- Review and adjust IAM policies as needed

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning**: This will delete all infrastructure including the EKS cluster and all data.

