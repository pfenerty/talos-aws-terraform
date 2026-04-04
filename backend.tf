# Terraform Backend Configuration
#
# Backend resources created successfully!
# Uncomment to enable remote state storage.

terraform {
  backend "s3" {
    bucket         = "talos-cluster-tf-state-u9ls3mt7"
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "talos-cluster-terraform-lock"
    encrypt        = true
  }
}
