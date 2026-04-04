#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Terraform Backend Bootstrap ===${NC}"
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo "Error: main.tf not found. Please run this script from the bootstrap-backend directory."
    exit 1
fi

# Get configuration
read -p "Enter AWS region [us-east-1]: " REGION
REGION=${REGION:-us-east-1}

read -p "Enter project name [talos-cluster]: " PROJECT
PROJECT=${PROJECT:-talos-cluster}

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
region       = "$REGION"
project_name = "$PROJECT"
EOF

echo -e "${YELLOW}Created terraform.tfvars with:${NC}"
cat terraform.tfvars
echo ""

# Initialize and apply
echo -e "${GREEN}Initializing Terraform...${NC}"
terraform init

echo ""
echo -e "${GREEN}Planning infrastructure...${NC}"
terraform plan

echo ""
read -p "Apply these changes? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Creating backend resources...${NC}"
terraform apply -auto-approve

# Get outputs
BUCKET=$(terraform output -raw s3_bucket_name)
TABLE=$(terraform output -raw dynamodb_table_name)

echo ""
echo -e "${GREEN}=== Backend Created Successfully ===${NC}"
echo ""
echo "S3 Bucket: $BUCKET"
echo "DynamoDB Table: $TABLE"
echo ""

# Update parent backend.tf
BACKEND_FILE="../backend.tf"
cat > "$BACKEND_FILE" <<EOF
# Terraform Backend Configuration
#
# Backend resources created successfully!
# State will be stored in S3 with DynamoDB locking.

terraform {
  backend "s3" {
    bucket         = "$BUCKET"
    key            = "terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$TABLE"
    encrypt        = true
  }
}
EOF

echo -e "${GREEN}Updated $BACKEND_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. cd .."
echo "2. terraform init (to migrate state to S3)"
echo "3. terraform plan && terraform apply"
