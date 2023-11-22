module "cilium" {
  source           = "./cilium"
  cilium_version   = var.cilium_version
  k8s_service_host = var.k8s_service_host
}

resource "random_uuid" "cluster_flux_id" {}

resource "flux_bootstrap_git" "this" {
  count = var.enables.flux.enabled ? 1 : 0

  depends_on = [module.cilium]

  path = "clusters/${random_uuid.cluster_flux_id.result}"

  kustomization_override = file("${path.module}/flux.patch.yaml")
}

module "ebs" {
  count = var.enables.extras.ebs ? 1 : 0

  source         = "./ebs"
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
}

module "linkerd" {
  count  = var.enables.extras.linkerd ? 1 : 0
  source = "./linkerd"

  depends_on = [flux_bootstrap_git.this]
}

module "autoscaler" {
  count  = var.enables.extras.autoscaler ? 1 : 0
  source = "./autoscaler"

  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = var.region

  depends_on = [flux_bootstrap_git.this]
}

module "vault" {
  count = var.enables.extras.vault ? 1 : 0
  source = "./vault"

  project_name   = var.project_name
  region         = var.region

  depends_on = [flux_bootstrap_git.this]
}

resource "kubernetes_secret" "aws_lb_config" {
  count = var.enables.flux.enabled ? 1 : 0

  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "aws-loadbalancer-config"
    namespace = "flux-system"
  }

  data = {
    dns_name = var.k8s_service_host
  }
}