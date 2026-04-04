variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "cilium_version" {
  type = string
}

variable "k8s_service_host" {
  type = string
}

variable "argocd_version" {
  type = string
}

variable "enables" {
  type = object({
    argocd = object({
      enabled             = bool
      git_url             = string
      git_branch          = string
      git_path            = string
      ssh_key             = string
      admin_password_hash = string
    })
    extras = object({
      ebs        = bool
      linkerd    = bool
      autoscaler = bool
    })
  })
  default = {
    argocd = {
      enabled             = false
      git_url             = ""
      git_branch          = "main"
      git_path            = "bootstrap"
      ssh_key             = ""
      admin_password_hash = ""
    }
    extras = {
      ebs        = false
      linkerd    = false
      autoscaler = false
    }
  }
}