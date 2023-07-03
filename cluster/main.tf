data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = var.project_name
  cidr = var.vpc_cidr

  azs            = data.aws_availability_zones.available.names
  public_subnets = [for i, v in data.aws_availability_zones.available.names : cidrsubnet(var.vpc_cidr, 5, i)]
}

module "security" {
  source       = "./security"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  admin_cidr   = var.admin_cidr
}

module "load_balancer" {
  source       = "./load_balancer"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnets      = module.vpc.public_subnets
}

module "control_plane" {
  source          = "./nodes"
  node_type       = "control_plane"
  project_name    = var.project_name
  talos_version   = var.talos_version
  user_data       = var.control_plane_config
  region          = var.region
  security_groups = [module.security.all_sgid, module.security.control_plane_sgid]
  subnets         = module.vpc.public_subnets
  min_nodes       = var.control_plane_nodes
  max_nodes       = var.control_plane_nodes
  instance_type   = var.control_plane_instance_type
}

module "workers" {
  count           = var.max_worker_nodes == 0 ? 0 : 1
  source          = "./nodes"
  node_type       = "worker"
  project_name    = var.project_name
  talos_version   = var.talos_version
  user_data       = var.worker_config
  region          = var.region
  security_groups = [module.security.all_sgid]
  subnets         = module.vpc.public_subnets
  min_nodes       = var.min_worker_nodes
  max_nodes       = var.max_worker_nodes
  instance_type   = var.worker_instance_type
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = module.control_plane.autoscaling_group_name
  lb_target_group_arn    = module.load_balancer.target_group_arn
}