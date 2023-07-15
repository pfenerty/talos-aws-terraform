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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.21.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.9.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.0.0"
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
      project_name = var.project_name
    }
  }
}

provider "kubernetes" {
  host                   = yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["server"]
  cluster_ca_certificate = base64decode(yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

  client_certificate = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-certificate-data"])
  client_key         = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-key-data"])
}

provider "helm" {
  kubernetes {
    host                   = yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
}

provider "flux" {
  kubernetes = {
    host                   = yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos.kubeconfig)["users"][0]["user"]["client-key-data"])
  }
  git = {
    url    = "ssh://github.com/pfenerty/flux-bootstrap.git"
    branch = "talos"
    ssh = {
      username    = "git"
      private_key = <<EOT
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBhmDEQqq4ukAa8UFKr3wLgWN7G1I5FUQZx5JSZVl3MaQAAAKCzp5iDs6eY
gwAAAAtzc2gtZWQyNTUxOQAAACBhmDEQqq4ukAa8UFKr3wLgWN7G1I5FUQZx5JSZVl3MaQ
AAAED9/oOS50FSjCVtOMmPPPO+IyqJughJeORVbVFvGNJTeGGYMRCqri6QBrxQUqvfAuBY
3sbUjkVRBnHklJlWXcxpAAAAG3BhdHJpY2tmZW5lcnR5QEdMYURPUy5sb2NhbAEC
-----END OPENSSH PRIVATE KEY-----
EOT
    }
  }
}