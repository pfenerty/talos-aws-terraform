terraform {
  required_version = ">= 1.9"

  # No provider blocks. This is a module, so the configuration of every
  # provider below belongs to whoever calls it - see examples/full for the
  # configuration this module expects to inherit, and why the kubernetes,
  # helm and flux providers have to be built from the cluster module's
  # outputs rather than declared up front.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
