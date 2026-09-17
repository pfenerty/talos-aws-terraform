variable "project_name" {
  type        = string
  description = "Names every AWS resource, and the cluster itself."
}

variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to create the cluster in."
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "Named profile from the shared AWS config. Null uses the standard credential chain."
}

variable "allowed_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach the Kubernetes and Talos APIs. Narrow this to your own address."
}

variable "availability_zones" {
  type        = list(string)
  default     = null
  description = "Availability Zones to place subnets in. Null uses every zone the region reports."
}

variable "flux" {
  type = object({
    enabled    = bool
    git_url    = string
    git_branch = string
    ssh_key    = string
  })
  sensitive = true
  default = {
    enabled    = false
    git_url    = ""
    git_branch = ""
    ssh_key    = ""
  }
  description = "Flux bootstrap configuration."
}

variable "extras" {
  type = object({
    ebs       = bool
    karpenter = bool
  })
  default = {
    ebs       = false
    karpenter = false
  }
  description = "Terraform-managed AWS resources the Flux bootstrap repository consumes. Require Flux."
}
