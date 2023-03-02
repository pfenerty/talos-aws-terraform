variable "project_name" {
  type = string
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

variable "vpc_id" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "availability_zone" {
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