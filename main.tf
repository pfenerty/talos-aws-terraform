resource "null_resource" "prechecks" {
  lifecycle {
    # Git URL and SSH key are optional - only required if you want GitOps bootstrap
    # precondition {
    #   condition     = !(var.post_install.argocd.enabled && var.post_install.argocd.git_url != "" && var.post_install.argocd.ssh_key == "")
    #   error_message = "If Argo CD git_url is provided, you must also provide an ssh_key"
    # }

    precondition {
      condition     = !(!var.post_install.argocd.enabled && (var.post_install.extras.ebs || var.post_install.extras.autoscaler || var.post_install.extras.linkerd))
      error_message = "Post Install extras are enabled but Argo CD post install is not. The extras are designed with Argo CD. Enable Argo CD post install if you want to use them."
    }
  }
}

module "networking" {
  source                      = "./cloud_infra/networking"
  project_name                = var.project_name
  region                      = var.region
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
}

module "talos_config" {
  source             = "./talos/config"
  project_name       = var.project_name
  load_balancer_dns  = module.networking.load_balancer_dns
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version

  providers = {
    talos = talos
  }
}

module "compute" {
  source                          = "./cloud_infra/compute"
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

data "aws_instances" "control_plane_instances" {
  depends_on = [
    module.compute
  ]
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.compute.control_plane_autoscaling_group_name]
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

resource "time_sleep" "wait_for_cluster_ready" {
  depends_on = [
    module.networking,
    module.compute,
    module.talos_bootstrap
  ]
  create_duration = "90s"
}

module "post_install" {
  source = "./post-install"

  depends_on = [
    module.networking,
    module.compute,
    module.talos_bootstrap,
    time_sleep.wait_for_cluster_ready
  ]

  project_name = var.project_name
  region       = var.region

  cilium_version   = var.cilium_version
  argocd_version   = var.argocd_version
  k8s_service_host = module.networking.load_balancer_dns

  enables = var.post_install
}