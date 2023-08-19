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

variable "enables" {
  type = object({
    flux = object({
      enabled    = bool
      git_url    = string
      git_branch = string
      ssh_key    = string
    })
    extras = object({
      ebs        = bool
      linkerd    = bool
      autoscaler = bool
    })
  })
  default = {
    flux = {
      enabled    = false
      git_url    = ""
      git_branch = ""
      ssh_key    = ""
    }
    extras = {
      ebs        = false
      linkerd    = false
      autoscaler = false
    }
  }
}