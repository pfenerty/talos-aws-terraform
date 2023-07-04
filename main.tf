module "talos_config" {
  source             = "./talos/config"
  project_name       = var.project_name
  endpoint           = "https://${module.cluster.load_balancer_dns}:443"
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version

  cni                = var.enable_cilium ? "cilium" : "flannel"
  disable_kube_proxy = var.cilium_replace_kube_proxy
}

module "cluster" {
  source                      = "./cluster"
  project_name                = var.project_name
  talos_version               = var.talos_version
  control_plane_config        = module.talos_config.machineconfig_controlplane
  worker_config               = module.talos_config.machineconfig_worker
  region                      = var.region
  subnet_cidr                 = var.subnet_cidr
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
  control_plane_nodes         = var.control_plane_nodes
  control_plane_instance_type = var.control_plane_node_instance_type
  worker_nodes                = var.worker_nodes
  worker_instance_type        = var.worker_node_instance_type
}

module "talos_bootstrap" {
  source           = "./talos/bootstrap"
  talos_config     = module.talos_config.talosconfig
  control_plane_ip = module.cluster.control_plane_public_ips[0]
}


# resource "time_sleep" "wait_for_cluster_ready" {
#   depends_on      = [module.talos_bootstrap]
#   create_duration = "120s"
# }

# module "post_install" {
#   source = "./post-install"

#   depends_on = [
#     time_sleep.wait_for_cluster_ready
#   ]

#   cilium                   = var.enable_cilium
#   cilium_version           = var.cilium_version
#   cilium_k8s_service_host  = module.cluster.load_balancer_dns
#   cilium_k8s_service_port  = 443
#   cilium_enable_hubble     = var.enable_cilium_hubble
#   cilium_proxy_replacement = var.cilium_replace_kube_proxy
# }