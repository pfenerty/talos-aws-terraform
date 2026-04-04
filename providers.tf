terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.56.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.21.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
  }
}

provider "aws" {
  region                   = var.region
  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "default"
  default_tags {
    tags = {
      "kubernetes.io/cluster/${var.project_name}" = "owned"
    }
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
  kubernetes {
    host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
}
