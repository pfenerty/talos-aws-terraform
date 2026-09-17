# A complete cluster, bootstrapped in one `terraform apply`.
#
# Most of this file is provider configuration, and that is the point: a
# reusable module cannot configure providers on the caller's behalf, so the
# wiring below is what you copy. Everything from `module "talos_cluster"`
# down is the actual configuration.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.65" }
    talos      = { source = "siderolabs/talos", version = "~> 0.11" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.2" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    flux       = { source = "fluxcd/flux", version = "~> 1.9" }
  }
}

provider "aws" {
  region = var.region

  # Left to the standard AWS credential chain so this works unchanged under a
  # CI role, SSO, or an assumed role. Set profile to pin a named profile.
  profile = var.aws_profile
}

provider "talos" {}

# The kubernetes, helm and flux providers are configured from the cluster's
# own kubeconfig, which does not exist until the cluster module has applied.
# Terraform handles that: a provider whose configuration is not yet known is
# not instantiated until apply, and every resource belonging to it is planned
# as "known after apply". It does mean these providers cannot be used for
# data sources that must be read during plan.
locals {
  kubeconfig = yamldecode(module.talos_cluster.kubeconfig)
  kube = {
    host                   = local.kubeconfig["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
    client_certificate     = base64decode(local.kubeconfig["users"][0]["user"]["client-certificate-data"])
    client_key             = base64decode(local.kubeconfig["users"][0]["user"]["client-key-data"])
  }
}

provider "kubernetes" {
  host                   = local.kube.host
  cluster_ca_certificate = local.kube.cluster_ca_certificate
  client_certificate     = local.kube.client_certificate
  client_key             = local.kube.client_key
}

provider "helm" {
  kubernetes = local.kube
}

provider "flux" {
  kubernetes = local.kube

  git = {
    # The provider requires a git block even when Flux bootstrap is disabled,
    # so this falls back to a placeholder rather than being conditional.
    url    = var.flux.enabled ? var.flux.git_url : "ssh://github.com"
    branch = var.flux.git_branch
    ssh = {
      username    = "git"
      private_key = var.flux.ssh_key
    }
  }
}

module "talos_cluster" {
  source = "../../"

  project_name = var.project_name
  region       = var.region

  # Both APIs default to being reachable from the internet. The Talos API is
  # the one to care about: port 50000 administers the machines themselves.
  talos_api_allowed_cidr      = var.allowed_cidr
  kubernetes_api_allowed_cidr = var.allowed_cidr

  # Pinning these stops the subnet layout moving if AWS adds an Availability
  # Zone to the region. Read them off the availability_zones output of a
  # first apply.
  availability_zones = var.availability_zones

  post_install = {
    flux   = var.flux
    extras = var.extras
  }
}

output "cluster_endpoint" {
  value = module.talos_cluster.cluster_endpoint
}

# `terraform output -raw kubeconfig > ~/.kube/talos`. Marked sensitive so it
# does not land in the apply log of whatever is running this.
output "kubeconfig" {
  value     = module.talos_cluster.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.talos_cluster.talosconfig
  sensitive = true
}
