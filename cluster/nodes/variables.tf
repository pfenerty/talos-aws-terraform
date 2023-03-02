variable "project_name" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "node_type" {
  type = string
}

variable "user_data" {
  type = string
}

variable "security_groups" {
  type = list(string)
}

variable "subnets" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "min_nodes" {
  type = number
}

variable "max_nodes" {
  type = number
}