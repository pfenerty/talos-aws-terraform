variable "name" {
  type        = string
  description = "Name of the role and of the policy attached to it. Prefixed with the project name by the caller, as every other AWS resource here is."
}

variable "service_account" {
  type        = string
  description = "Name of the Kubernetes service account allowed to assume this role. Must match what the workload's chart actually creates: the trust policy compares it exactly, and a mismatch fails at AssumeRoleWithWebIdentity rather than at apply."
}

variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace of that service account."
}

variable "policy" {
  type        = string
  description = "The permissions policy, as JSON. What the role may do once assumed."
}

variable "oidc" {
  description = "The cluster's IAM identity provider. Pass the oidc module's outputs."
  type = object({
    provider_arn = string
    issuer_host  = string
  })
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the role and policy."
}
