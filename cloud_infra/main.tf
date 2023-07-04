data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "talos" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-amd64$"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = var.project_name
  cidr = var.vpc_cidr

  azs            = data.aws_availability_zones.available.names
  public_subnets = [for i, v in data.aws_availability_zones.available.names : cidrsubnet(var.vpc_cidr, 5, i)]
}

module "cluster_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = var.project_name
  description = "Allow all intra-cluster and egress traffic"
  vpc_id      = module.vpc.vpc_id

  ingress_with_self = [
    {
      rule = "all-all"
    },
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 50000
      to_port     = 50000
      protocol    = "tcp"
      cidr_blocks = var.talos_api_allowed_cidr
      description = "Talos API Access"
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "kubernetes_api_sg" {
  source  = "terraform-aws-modules/security-group/aws//modules/https-443"
  version = "~> 4.0"

  name                = "${var.project_name}-k8s-api"
  description         = "Allow access to the Kubernetes API"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = [var.kubernetes_api_allowed_cidr]
}

module "elb_k8s_elb" {
  source  = "terraform-aws-modules/elb/aws"
  version = "~> 4.0"

  name    = "${var.project_name}-k8s-api"
  subnets = module.vpc.public_subnets
  security_groups = [
    module.cluster_sg.security_group_id,
    module.kubernetes_api_sg.security_group_id,
  ]

  listener = [
    {
      lb_port           = 443
      lb_protocol       = "tcp"
      instance_port     = 6443
      instance_protocol = "tcp"
    },
  ]

  health_check = {
    target              = "tcp:6443"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  number_of_instances = var.control_plane_nodes
  instances           = module.control_plane_nodes.*.id
}

module "control_plane_nodes" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 4.0"

  count = var.control_plane_nodes

  name          = "${var.project_name}-control-plane-${count.index}"
  ami           = data.aws_ami.talos.id
  monitoring    = true
  instance_type = var.control_plane_instance_type
  subnet_id     = element(module.vpc.public_subnets, count.index)

  vpc_security_group_ids = [module.cluster_sg.security_group_id]

  root_block_device = [
    {
      volume_size = 100
    }
  ]
}

module "worker_nodes" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 4.0"

  count = var.worker_nodes

  name          = "${var.project_name}-control-plane-${count.index}"
  ami           = data.aws_ami.talos.id
  monitoring    = true
  instance_type = var.worker_instance_type
  subnet_id     = element(module.vpc.public_subnets, count.index)

  vpc_security_group_ids = [module.cluster_sg.security_group_id]

  root_block_device = [
    {
      volume_size = 100
    }
  ]
}