variable "app_version" {
  type = string
}

variable "k8s_service_host" {
  type = string
}

variable "k8s_service_port" {
  type = number
}

variable "proxy_replacement" {
  type = bool
}

variable "enable_hubble" {
  type = bool
}