variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC."
  type        = string
  default     = "172.31.0.0/16"
}

variable "talos_version" {
  type = string
}

variable "control_plane_config" {
  type = string
}

variable "worker_config" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "talos_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Talos API"
  type        = string
}

variable "kubernetes_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Kubernetes API"
  type        = string
}

variable "control_plane_instance_type" {
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "control_plane_nodes" {
  type    = number
  default = 1
}

variable "worker_nodes" {
  type    = number
  default = 1
}