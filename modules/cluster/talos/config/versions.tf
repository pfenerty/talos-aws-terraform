terraform {
  required_version = ">= 1.9"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
