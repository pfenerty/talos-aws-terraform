variable "project_name" {
  type        = string
  description = "Project name, used to name the IAM resources and as the Karpenter cluster name."
}

variable "region" {
  type        = string
  description = "AWS region, passed to Karpenter so it launches nodes in the right place."
}

variable "cilium_version" {
  type        = string
  description = "Cilium chart version to install."
}

variable "k8s_service_host" {
  type        = string
  description = "Control plane load balancer DNS, published to the cluster in a secret."
}

variable "enables" {
  type = object({
    flux = object({
      enabled    = bool
      git_url    = string
      git_branch = string
      ssh_key    = string
    })
    extras = object({
      ebs       = bool
      karpenter = bool
    })
  })
  sensitive   = true
  description = "Mirror of the root post_install variable: which post-install steps to run, and the Flux git credentials."
  default = {
    flux = {
      enabled    = false
      git_url    = ""
      git_branch = ""
      ssh_key    = ""
    }
    extras = {
      ebs       = false
      karpenter = false
    }
  }
}
variable "pod_cidr" {
  type        = string
  description = "Pod subnet CIDR"
}

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint, handed to Karpenter"
}

variable "worker_instance_profile_name" {
  type        = string
  description = "Instance profile Karpenter launches nodes into"
}

variable "worker_iam_role_arn" {
  type        = string
  description = "Role behind worker_instance_profile_name, scoping Karpenter's iam:PassRole grant"
}

variable "worker_ami_id" {
  type        = string
  description = "Talos AMI Karpenter launches nodes from"
}

variable "karpenter_worker_machine_config" {
  type        = string
  description = "Talos worker machine config used as the EC2NodeClass user data"
  sensitive   = true
}
