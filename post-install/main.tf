module "cilium" {
  count  = var.cilium ? 1 : 0
  source = "./cilium"

  app_version   = var.cilium_version
  enable_hubble = var.cilium_enable_hubble

  k8s_service_host = var.cilium_k8s_service_host
  k8s_service_port = var.cilium_k8s_service_port

  proxy_replacement = var.cilium_proxy_replacement
}