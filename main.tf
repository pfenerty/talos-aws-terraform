module "cluster" {
  source                      = "./cloud_infra"
  project_name                = var.project_name
  talos_version               = var.talos_version
  region                      = var.region
  subnet_cidr                 = var.subnet_cidr
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
  control_plane_nodes         = var.control_plane_nodes
  control_plane_instance_type = var.control_plane_node_instance_type
  worker_nodes                = var.worker_nodes
  worker_instance_type        = var.worker_node_instance_type
}

module "talos" {
  source              = "./talos"
  project_name        = var.project_name
  endpoint            = "https://${module.cluster.load_balancer_dns}:443"
  control_plane_nodes = module.cluster.control_plane_nodes
  worker_nodes        = module.cluster.worker_nodes
  kubernetes_version  = var.kubernetes_version
  talos_version       = var.talos_version

  aws_topology = {
    region           = var.region
    az               = module.cluster.availability_zone
    cp_instance_type = var.control_plane_node_instance_type
    wk_instance_type = var.worker_node_instance_type
  }

  cni                = var.enable_cilium ? "cilium" : "flannel"
  disable_kube_proxy = var.cilium_replace_kube_proxy
}

resource "time_sleep" "wait_for_cluster_ready" {
  depends_on      = [module.talos]
  create_duration = "120s"
}

module "post_install" {
  source = "./post-install"

  depends_on = [
    module.cluster,
    module.talos,
    time_sleep.wait_for_cluster_ready
  ]

  cilium                   = var.enable_cilium
  cilium_version           = var.cilium_version
  cilium_k8s_service_host  = module.cluster.load_balancer_dns
  cilium_k8s_service_port  = 443
  cilium_enable_hubble     = var.enable_cilium_hubble
  cilium_proxy_replacement = var.cilium_replace_kube_proxy
}