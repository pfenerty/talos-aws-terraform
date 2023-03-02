resource "aws_subnet" "subnet" {
  vpc_id            = var.vpc_id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
}

module "security" {
  source       = "./security"
  project_name = var.project_name
  vpc_id       = var.vpc_id
  admin_cidr   = var.admin_cidr
}

module "load_balancer" {
  source       = "./load_balancer"
  project_name = var.project_name
  vpc_id       = var.vpc_id
  subnets      = [aws_subnet.subnet.id]
}

module "control_plane" {
  source          = "./nodes"
  node_type       = "control_plane"
  project_name    = var.project_name
  talos_version   = var.talos_version
  user_data       = var.control_plane_config
  security_groups = [module.security.all_sgid, module.security.control_plane_sgid]
  subnets         = [aws_subnet.subnet.id]
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
  security_groups = [module.security.all_sgid]
  subnets         = [aws_subnet.subnet.id]
  min_nodes       = var.min_worker_nodes
  max_nodes       = var.max_worker_nodes
  instance_type   = var.worker_instance_type
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = module.control_plane.autoscaling_group_name
  lb_target_group_arn    = module.load_balancer.target_group_arn
}