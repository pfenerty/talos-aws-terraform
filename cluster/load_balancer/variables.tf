variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "kubernetes_port" {
  type    = number
  default = 6443
}

variable "https_port" {
  type    = number
  default = 443
}