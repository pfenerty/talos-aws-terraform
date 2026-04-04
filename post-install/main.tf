module "cilium" {
  source           = "./cilium"
  cilium_version   = var.cilium_version
  k8s_service_host = var.k8s_service_host
}

module "ccm" {
  source       = "./ccm"
  project_name = var.project_name

  depends_on = [module.cilium]
}

module "argocd" {
  count = var.enables.argocd.enabled ? 1 : 0

  source = "./argocd"

  depends_on = [module.cilium, module.ccm]

  argocd_version      = var.argocd_version
  git_url             = var.enables.argocd.git_url
  git_branch          = var.enables.argocd.git_branch
  git_path            = var.enables.argocd.git_path
  git_ssh_key         = var.enables.argocd.ssh_key
  admin_password_hash = var.enables.argocd.admin_password_hash
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

  depends_on = [module.argocd]
}

module "autoscaler" {
  count  = var.enables.extras.autoscaler ? 1 : 0
  source = "./autoscaler"

  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = var.region

  depends_on = [module.argocd]
}

resource "kubernetes_secret" "aws_lb_config" {
  count = var.enables.argocd.enabled ? 1 : 0

  depends_on = [module.argocd]

  metadata {
    name      = "aws-loadbalancer-config"
    namespace = "argocd"
  }

  data = {
    dns_name = var.k8s_service_host
  }
}