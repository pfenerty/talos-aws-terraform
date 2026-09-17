variable "cilium_version" {
  type = string
}

variable "pod_cidr" {
  type        = string
  description = "Pod subnet CIDR, used as the Cilium strict-mode egress CIDR"
}
