resource "null_resource" "prechecks" {
  lifecycle {
    precondition {
      condition = !(var.enable_flux_post_install && var.flux_git_url == "")
      error_message = "If Flux post install is enabled, you must provide a git url to bootstrap flux"
    }

    precondition {
      condition = !(var.enable_flux_post_install && var.flux_git_branch == "")
      error_message = "If Flux post install is enabled, you must provide a git branch to bootstrap flux"
    }

    precondition {
      condition = !(var.enable_flux_post_install && var.flux_ssh_private_key == "")
      error_message = "If Flux post install is enabled, you must provide a git ssh key to bootstrap flux"
    }
  }
}

module "cluster" {
  source                      = "./cloud_infra"
  project_name                = var.project_name
  talos_version               = var.talos_version
  region                      = var.region
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
  load_balancer_dns   = module.cluster.load_balancer_dns
  control_plane_nodes = module.cluster.control_plane_nodes
  worker_nodes        = module.cluster.worker_nodes
  kubernetes_version  = var.kubernetes_version
  talos_version       = var.talos_version

  cilium                   = var.enable_cilium
  cilium_version           = var.cilium_version
  cilium_enable_hubble     = var.enable_cilium_hubble
  cilium_proxy_replacement = var.cilium_replace_kube_proxy

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
  count = var.enable_flux_post_install ? 1 : 0

  depends_on      = [
    module.cluster,
    module.talos
  ]
  create_duration = "90s"
}

module "post_install" {
  count = var.enable_flux_post_install ? 1 : 0

  source = "./post-install"

  depends_on = [
    module.cluster,
    module.talos,
    time_sleep.wait_for_cluster_ready
  ]

  providers = {
    flux = flux
  }

  project_name = var.project_name
  region = var.region
}

