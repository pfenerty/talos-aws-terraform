terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.56.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.1.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.9.0"
    }
  }
}