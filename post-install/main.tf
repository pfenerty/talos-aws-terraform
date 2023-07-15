module "cilium" {
  count  = var.cilium ? 1 : 0
  source = "./cilium"

  app_version   = var.cilium_version
  enable_hubble = var.cilium_enable_hubble

  k8s_service_host = var.cilium_k8s_service_host
  k8s_service_port = var.cilium_k8s_service_port

  proxy_replacement = var.cilium_proxy_replacement
}

module "ebs" {
  source = "./ebs"
  project_name = var.project_name
}

resource "random_uuid" "cluster_flux_id" {}

resource "flux_bootstrap_git" "this" {
  depends_on = [module.cilium]

  path = "clusters/${random_uuid.cluster_flux_id.result}"
}

module "linkerd" {
  source = "./linkerd"

  depends_on = [ flux_bootstrap_git.this ]
}