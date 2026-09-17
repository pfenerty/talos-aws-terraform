variable "project_name" {
  type        = string
  description = "Project name, used to name the EBS CSI driver's IAM user and policy."
}

variable "aws_account_id" {
  type        = string
  description = "Account ID, scoping the EBS CSI driver's policy to this account's volumes."
}
