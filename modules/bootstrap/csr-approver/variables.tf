variable "chart_version" {
  type        = string
  description = "kubelet-csr-approver chart version for the bootstrap install. Only ever used to create the release; Flux can own it afterwards."
}

variable "region" {
  type        = string
  description = "AWS region the cluster runs in. It decides the private DNS suffix the nodes register under, which the approver's name check is built from."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the cluster's VPC. Certificate requests may only carry addresses inside it."
}

variable "replicas" {
  type        = number
  description = "Replica count. The approver uses leader election, so extra replicas are failover and nothing else."

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
