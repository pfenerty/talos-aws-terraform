variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "control_plane_instance_type" {
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "control_plane_nodes" {
  type = number
}

variable "worker_nodes_min" {
  type = number
}

variable "worker_nodes_max" {
  type = number
}

variable "control_plane_machine_config" {
  type = string
}

variable "worker_machine_config" {
  type = string
}

variable "control_plane_security_group_id" {
  type = string
}

variable "internal_security_group_id" {
  type = string
}

variable "load_balancer_target_group_arn" {
  type = string
}