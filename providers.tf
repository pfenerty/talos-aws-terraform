terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.65.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.9.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.1"
    }
  }
}

provider "aws" {
  region = var.region

  # Left to the standard AWS credential chain so this works unchanged under a
  # CI role, SSO, or an assumed role. Set aws_profile to pin a named profile.
  profile = var.aws_profile

  default_tags {
    tags = merge({
      # Read by the AWS cloud controller manager to find the cluster's
      # resources; the name has to match the cluster name exactly.
      "kubernetes.io/cluster/${var.project_name}" = "owned"

      ManagedBy = "terraform"
      Project   = var.project_name
    }, var.additional_tags)
  }
}

provider "talos" {}

provider "kubernetes" {
  host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
  cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

  client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
  client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
}

provider "helm" {
  kubernetes = {
    host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
}

provider "flux" {
  kubernetes = {
    host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
  git = {
    url    = var.post_install.flux.enabled ? var.post_install.flux.git_url : "ssh://github.com"
    branch = var.post_install.flux.git_branch
    ssh = {
      username    = "git"
      private_key = var.post_install.flux.ssh_key
    }
  }
}
