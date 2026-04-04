# Terraform Backend Bootstrap

This directory contains Terraform configuration to create the S3 bucket and DynamoDB table needed for remote state storage.

## Usage

### 1. Create the backend resources

```bash
cd bootstrap-backend
terraform init
terraform apply
```

This will create:
- S3 bucket: `<project_name>-terraform-state`
- DynamoDB table: `<project_name>-terraform-lock`

### 2. Configure the main project

After the resources are created, a `backend.tf` file will be generated in the parent directory. 

### 3. Initialize the backend

```bash
cd ..
terraform init
```

Terraform will prompt you to migrate your state to the S3 backend.

## Customization

Edit the variables in `main.tf` to customize:
- `region`: AWS region (default: us-east-1)
- `project_name`: Project name prefix (default: talos-cluster)

Or create a `terraform.tfvars` file:

```hcl
region       = "us-west-2"
project_name = "my-cluster"
```

## Cleanup

To destroy the backend resources (only after destroying the main infrastructure):

```bash
# First, remove the backend configuration from parent directory
# Then destroy the backend resources
terraform destroy
```

**Warning**: Never destroy these resources while they contain active Terraform state!
