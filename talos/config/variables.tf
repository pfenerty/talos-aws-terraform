variable "project_name" {
  type        = string
  description = "Project name, used as the Talos cluster name."
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version the machine secrets and configs are generated for."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version written into the machine configs."
}

variable "load_balancer_dns" {
  type        = string
  description = "DNS name of the control plane load balancer, used as the cluster endpoint."
}
variable "pod_cidr" {
  type        = string
  description = "Pod subnet CIDR"
}
