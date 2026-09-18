variable "bucket_name" {
  type        = string
  description = "Name of the bucket the OIDC discovery documents are published to. Decided by the cluster module, because the issuer URL built from it is baked into the API server's machine config."
}

variable "issuer_url" {
  type        = string
  description = "URL the API server names as the issuer of its service account tokens. Must be the HTTPS URL of the bucket above, and must match the iss claim in the tokens byte for byte."
}

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint, read to fetch the cluster's own discovery documents."
}

variable "kubernetes_client_configuration" {
  description = "Admin client certificate for the Kubernetes API. The discovery endpoints are not anonymous on this cluster, so reading them needs one."
  sensitive   = true
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}
