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

provider "helm" {
  kubernetes {
    host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
}