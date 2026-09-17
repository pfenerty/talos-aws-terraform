variable "cilium_version" {
  type        = string
  description = "Cilium chart version for the bootstrap install. Only ever used to create the release; Flux owns it afterwards."
}

variable "operator_replicas" {
  type        = number
  description = "Replica count for cilium-operator. The chart default of 2 carries a required anti-affinity on hostname, so this must not exceed the number of nodes the cluster is created with."

  validation {
    condition     = var.operator_replicas >= 1
    error_message = "operator_replicas must be at least 1."
  }
}

variable "hubble_ca_validity_hours" {
  type        = number
  description = "Lifetime of the self-signed Hubble trust anchor, in hours."
}
