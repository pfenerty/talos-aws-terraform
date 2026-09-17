module "cilium" {
  source         = "./cilium"
  cilium_version = var.cilium_version
  pod_cidr       = var.pod_cidr
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

module "karpenter" {
  count  = var.enables.extras.karpenter ? 1 : 0
  source = "./karpenter"

  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = var.region

  cluster_endpoint           = var.cluster_endpoint
  node_instance_profile_name = var.worker_instance_profile_name
  node_iam_role_arn          = var.worker_iam_role_arn
  node_ami_id                = var.worker_ami_id
  node_user_data             = var.karpenter_worker_machine_config

  depends_on = [flux_bootstrap_git.this]
}

resource "kubernetes_secret_v1" "aws_lb_config" {
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