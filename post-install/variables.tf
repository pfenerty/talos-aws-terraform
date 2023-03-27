variable "cilium" {
  type = bool
}

variable "cilium_version" {
  type = string
}

variable "cilium_k8s_service_host" {
  type = string
}

variable "cilium_k8s_service_port" {
  type = number
}

variable "cilium_proxy_replacement" {
  type = bool
}

variable "cilium_enable_hubble" {
  type = bool
}