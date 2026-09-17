variable "cilium_version" {
  type        = string
  description = "Cilium chart version to install."
}

variable "pod_cidr" {
  type        = string
  description = "Pod subnet CIDR, used as the Cilium strict-mode egress CIDR"
}
