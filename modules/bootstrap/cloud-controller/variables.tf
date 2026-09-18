variable "project_name" {
  type        = string
  description = "Project name, used as the role name prefix and as the cloud controller's KubernetesClusterID - which must match the kubernetes.io/cluster tag on the cluster's resources."
}

variable "region" {
  type        = string
  description = "AWS region the cluster runs in. Set explicitly because the controller can no longer read it from instance metadata."
}

variable "vpc_id" {
  type        = string
  description = "VPC the cluster runs in."
}

variable "subnet_id" {
  type        = string
  description = "Any subnet in that VPC. Used only to build the controller's synthetic self-instance; load balancer placement is decided by subnet tags."
}

variable "token_path" {
  type        = string
  description = "Path the projected service account token is mounted at in the controller's pod. Must match the volume mount in the Flux bootstrap repository."
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
  description = "Tags applied to every resource this module creates."
}
