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
  worker_nodes_min                 = var.worker_nodes_min
  worker_nodes_max                 = var.worker_nodes_max
  worker_node_instance_type        = var.worker_node_instance_type

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  pod_cidr           = var.pod_cidr

  config_output_path = var.config_output_path
}

module "bootstrap" {
  source = "./modules/bootstrap"

  cluster = module.cluster.bootstrap_inputs

  flux   = var.post_install.flux
  extras = var.post_install.extras

  cilium_bootstrap_version = var.cilium_bootstrap_version
  hubble_ca_validity_hours = var.hubble_ca_validity_hours
  cluster_health_timeout   = var.cluster_health_timeout
}
