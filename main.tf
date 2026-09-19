# Batteries-included entry point: creates the cluster and bootstraps it in one
# apply. It is a convenience over the two modules below, which is all it is -
# if you need several clusters in one configuration, call ./modules/cluster
# and ./modules/bootstrap directly, because a `for_each` over this wrapper
# still needs one set of kubernetes/helm/flux provider configurations per
# cluster and Terraform has no way to produce those dynamically.
module "cluster" {
  source = "./modules/cluster"

  project_name    = var.project_name
  region          = var.region
  additional_tags = var.additional_tags

  availability_zones          = var.availability_zones
  vpc_cidr                    = var.vpc_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr

  control_plane_nodes              = var.control_plane_nodes
  control_plane_node_instance_type = var.control_plane_node_instance_type
  control_plane_node_architecture  = var.control_plane_node_architecture
  control_plane_root_volume_size   = var.control_plane_root_volume_size
  worker_nodes_min                 = var.worker_nodes_min
  worker_nodes_max                 = var.worker_nodes_max
  worker_node_instance_type        = var.worker_node_instance_type
  worker_node_architecture         = var.worker_node_architecture
  worker_root_volume_size          = var.worker_root_volume_size

  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  pod_cidr           = var.pod_cidr
  hardening          = var.hardening

  machine_config_updates      = var.machine_config_updates
  kubernetes_talos_api_access = var.kubernetes_talos_api_access

  config_output_path = var.config_output_path
}

module "bootstrap" {
  source = "./modules/bootstrap"

  cluster = module.cluster.bootstrap_inputs

  flux   = var.post_install.flux
  extras = var.post_install.extras

  karpenter = var.karpenter

  cilium_bootstrap_version = var.cilium_bootstrap_version
  hubble_ca_validity_hours = var.hubble_ca_validity_hours
  cluster_health_timeout   = var.cluster_health_timeout

  # Data flow already orders this after the cluster's outputs, but not after
  # the machine config applies, which produce none. The health gate is the
  # thing that decides the apply succeeded, so it has to run after the last
  # change that could make the cluster unhealthy - including a kube-apiserver
  # restart from a config apply.
  depends_on = [module.cluster]
}
