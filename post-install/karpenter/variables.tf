variable "project_name" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint. Karpenter discovers this from the EKS API when it is not set, which is not an option for a self-managed cluster."
}

variable "node_instance_profile_name" {
  type        = string
  description = "Instance profile Karpenter launches nodes into. Reuses the worker profile so Karpenter never needs instance-profile write permissions."
}

variable "node_iam_role_arn" {
  type        = string
  description = "Role behind node_instance_profile_name, scoping the controller's iam:PassRole grant."
}

variable "node_ami_id" {
  type        = string
  description = "Talos AMI the EC2NodeClass selects. Pinned rather than discovered so Karpenter nodes cannot drift off the Talos version the rest of the cluster runs."
}

variable "node_user_data" {
  type        = string
  description = "Talos worker machine config used as the EC2NodeClass user data."
  sensitive   = true
}
