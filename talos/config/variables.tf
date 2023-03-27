variable "endpoint" {
  type = string
}

variable "project_name" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "cni" {
  type    = string
  default = "flannel"
}

variable "disable_kube_proxy" {
  type    = bool
  default = false
}