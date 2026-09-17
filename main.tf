module "networking" {
  source                      = "./cloud-infra/networking"
  project_name                = var.project_name
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
}

module "talos_config" {
  source             = "./talos/config"
  project_name       = var.project_name
  load_balancer_dns  = module.networking.load_balancer_dns
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  pod_cidr           = var.pod_cidr

  providers = {
    talos = talos
  }
}

module "compute" {
  source                          = "./cloud-infra/compute"
  project_name                    = var.project_name
  talos_version                   = var.talos_version
  region                          = var.region
  subnets                         = module.networking.public_subnets
  control_plane_security_group_id = module.networking.control_plane_security_group_id
  internal_security_group_id      = module.networking.internal_security_group_id
  control_plane_nodes             = var.control_plane_nodes
  control_plane_instance_type     = var.control_plane_node_instance_type
  worker_nodes_min                = var.worker_nodes_min
  worker_nodes_max                = var.worker_nodes_max
  worker_instance_type            = var.worker_node_instance_type
  control_plane_machine_config    = module.talos_config.control_plane_machine_config
  worker_machine_config           = module.talos_config.worker_machine_config
  load_balancer_target_group_arn  = module.networking.load_balancer_target_group_arn
}

# Bootstrap only has to reach one control plane node, so this takes the first.
# public_ips and private_ips are parallel lists describing the same instances
# in the same order, which is why both are indexed identically and why neither
# may be sorted independently of the other.
data "aws_instances" "control_plane_instances" {
  depends_on = [
    module.compute
  ]
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.compute.control_plane_autoscaling_group_name]
  }

  lifecycle {
    postcondition {
      condition     = length(self.public_ips) > 0 && length(self.private_ips) > 0
      error_message = "No running instances found in the control plane autoscaling group. The group may still be launching, or its instances may be failing to start."
    }
  }
}

data "aws_instances" "worker_instances" {
  depends_on = [
    module.compute
  ]
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.compute.worker_autoscaling_group_name]
  }
}

module "talos_bootstrap" {
  source               = "./talos/bootstrap"
  client_configuration = module.talos_config.client_configuration
  public_ip            = data.aws_instances.control_plane_instances.public_ips[0]
  private_ip           = data.aws_instances.control_plane_instances.private_ips[0]

  providers = {
    talos = talos
  }
}

# Blocks until the cluster reports healthy - etcd quorum, kubelet up on every
# node, control plane components live - rather than waiting out a fixed delay
# and hoping. This is the Talos provider's own readiness check, so it knows
# what healthy means; a timer did not.
data "talos_cluster_health" "this" {
  depends_on = [
    module.networking,
    module.compute,
    module.talos_bootstrap
  ]

  client_configuration = module.talos_config.client_configuration
  control_plane_nodes  = data.aws_instances.control_plane_instances.private_ips
  worker_nodes         = data.aws_instances.worker_instances.private_ips

  # Node addresses are private, so the client reaches them through a control
  # plane node's public address.
  endpoints = data.aws_instances.control_plane_instances.public_ips

  timeouts = {
    read = var.cluster_health_timeout
  }
}

module "post_install" {
  source = "./post-install"

  depends_on = [
    module.networking,
    module.compute,
    module.talos_bootstrap,
    data.talos_cluster_health.this
  ]

  providers = {
    flux = flux
  }

  project_name = var.project_name
  region       = var.region

  cilium_version   = var.cilium_version
  k8s_service_host = module.networking.load_balancer_dns
  pod_cidr         = var.pod_cidr

  cluster_endpoint                = "https://${module.networking.load_balancer_dns}:443"
  worker_instance_profile_name    = module.compute.worker_instance_profile_name
  worker_iam_role_arn             = module.compute.worker_iam_role_arn
  worker_ami_id                   = module.compute.talos_ami_id
  karpenter_worker_machine_config = module.talos_config.karpenter_worker_machine_config

  enables = var.post_install
}
