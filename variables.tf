variable "region" {
  type        = string
  default     = "us-east-1"
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
  default     = "my-cluster"
  description = "Project name, used to give names to various resources"
}

variable "control_plane_nodes" {
  type        = number
  default     = 3
  description = "Number of control plane nodes"
}

variable "control_plane_node_instance_type" {
  type        = string
  default     = "t3.small"
  description = "AWS EC2 instance type for control plane nodes"
}

variable "worker_nodes" {
  type        = number
  default     = 0
  description = "Minimum number of worker nodes for the autoscaling group"
}

variable "worker_node_instance_type" {
  type        = string
  default     = "t3.small"
  description = "AWS EC2 instance type for worker nodes"
}

variable "talos_version" {
  type        = string
  default     = "v1.4.7"
  description = "Talos Linux version"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.27.4"
  description = "Kubernetes version"
}

variable "enable_cilium" {
  type        = bool
  default     = true
  description = "Use Cilium as the CNI, replaces Talos default flannel"
}

variable "cilium_version" {
  type        = string
  default     = "1.14.0"
  description = "Version of Cilium to deploy"
}

variable "enable_cilium_hubble" {
  type        = bool
  default     = true
  description = "Enable Cilium Hubble"
}

variable "cilium_replace_kube_proxy" {
  type        = bool
  default     = true
  description = "Use Cilium to replace Kube Proxy"
}

variable "enable_flux_post_install" {
  type        = bool
  default     = true
  description = "Enable flux bootstrap and post install resources"
}

variable "flux_git_url" {
  type        = string
  description = "Git URL to initialize flux-system"
  default = ""
}

variable "flux_git_branch" {
  type        = string
  description = "Git branch to initialize flux-system"
  default = ""
}

variable "flux_ssh_private_key" {
  type        = string
  description = "SSH key to use for Flux git auth"
  default = ""
}