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

variable "admin_cidr" {
  type = string
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

variable "min_worker_nodes" {
  type    = number
  default = 1
}

variable "max_worker_nodes" {
  type    = number
  default = 1
}