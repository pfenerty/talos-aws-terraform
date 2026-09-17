variable "project_name" {
  type        = string
  description = "Project name, used to name and tag the network resources and as the Karpenter discovery tag value."
}

variable "availability_zones" {
  description = "Availability Zones to create subnets in. Null means every zone the region currently reports, which is convenient but means the layout changes if AWS adds a zone; pin it for anything long-lived."
  type        = list(string)
  default     = null
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC."
  type        = string
  default     = "172.31.0.0/16"
}

variable "talos_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Talos API"
  type        = string
}

variable "kubernetes_api_allowed_cidr" {
  description = "The CIDR from which to allow to access the Kubernetes API"
  type        = string
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource. Carries the kubernetes.io/cluster tag the AWS cloud controller manager looks for, so it is not optional in practice - the parent module always sets it."
}
