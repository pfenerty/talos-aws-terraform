variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to create infastructure in"
}

variable "talos_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Talos API"
  type        = string
  default     = "0.0.0.0/0"
}

variable "kubernetes_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Kubernetes API"
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_name" {
  type        = string
  default     = "talos-cluster"
  description = "Project name, used to give names to various resources"
}

variable "control_plane_nodes" {
  type        = number
  default     = 1
  description = "Number of control plane nodes"
}

variable "control_plane_node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "AWS EC2 instance type for control plane nodes"
}

variable "worker_nodes_min" {
  type        = number
  default     = 1
  description = "Minimum number of worker nodes for the autoscaling group"
}

variable "worker_nodes_max" {
  type        = number
  default     = 5
  description = "Maximum number of worker nodes for the autoscaling group"
}

variable "worker_node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "AWS EC2 instance type for worker nodes"
}

# renovate: datasource=github-releases depName=siderolabs/talos
variable "talos_version" {
  type        = string
  default     = "v1.14.1"
  description = "Talos Linux version"
}

# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
variable "kubernetes_version" {
  type        = string
  default     = "1.37.0"
  description = "Kubernetes version"
}

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io
variable "cilium_version" {
  type        = string
  default     = "1.20.2"
  description = "Version of Cilium to deploy"
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod subnet CIDR. Set on the Talos machine config and reused as Cilium's strict-mode egress CIDR so the two cannot drift apart."
}

variable "post_install" {
  type = object({
    flux = object({
      enabled    = bool
      git_url    = string
      git_branch = string
      ssh_key    = string
    })
    extras = object({
      ebs        = bool
      linkerd    = bool
      autoscaler = bool
    })
  })
  default = {
    flux = {
      enabled    = false
      git_url    = ""
      git_branch = ""
      ssh_key    = ""
    }
    extras = {
      ebs        = false
      linkerd    = false
      autoscaler = false
    }
  }
}
