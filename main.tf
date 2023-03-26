provider "aws" {
  region                   = var.region
  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "default"
  default_tags {
    tags = {
      project_name = var.project_name
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["server"]
    cluster_ca_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])

    client_certificate = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(yamldecode(module.talos_bootstrap.kubeconfig)["users"][0]["user"]["client-key-data"])
  } 
}

module "talos_config" {
  source             = "./talos/config"
  project_name       = var.project_name
  endpoint           = "https://${module.cluster.load_balancer_dns}:443"
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
}

module "cluster" {
  source                      = "./cluster"
  project_name                = var.project_name
  talos_version               = var.talos_version
  control_plane_config        = module.talos_config.machineconfig_controlplane
  worker_config               = module.talos_config.machineconfig_worker
  vpc_id                      = var.vpc_id
  subnet_cidr                 = var.subnet_cidr
  availability_zone           = var.availability_zone
  admin_cidr                  = var.admin_cidr
  control_plane_nodes         = var.control_plane_nodes
  control_plane_instance_type = var.control_plane_node_instance_type
  min_worker_nodes            = var.min_worker_nodes
  max_worker_nodes            = var.max_worker_nodes
  worker_instance_type        = var.control_plane_node_instance_type
}

data "aws_instances" "control_plane_instances" {
  depends_on = [
    module.cluster
  ]
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.cluster.control_plane_asg_name]
  }
}

module "talos_bootstrap" {
  source           = "./talos/bootstrap"
  talos_config     = module.talos_config.talosconfig
  control_plane_ip = data.aws_instances.control_plane_instances.public_ips[0]
}


resource "time_sleep" "wait_2_minutes" {
  depends_on = [module.talos_bootstrap]

  create_duration = "120s"
}

resource "helm_release" "cilium" {
  depends_on = [
    time_sleep.wait_2_minutes
  ]

  name       = "cilium"
  repository = "https://helm.cilium.io"
  namespace  = "kube-system"
  chart      = "cilium"
  version    = "1.13.1"

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  set {
    name = "securityContext.privileged"
    value = "true"
  }
}