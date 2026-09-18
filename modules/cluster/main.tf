locals {
  # Applied to every resource this module creates. The cluster tag is read by
  # the AWS cloud controller manager to find the cluster's resources, so it
  # has to match the cluster name exactly. It lives here rather than in a
  # provider `default_tags` block because a reusable module does not get to
  # configure the consumer's provider.
  tags = merge({
    "kubernetes.io/cluster/${var.project_name}" = "owned"

    ManagedBy = "terraform"
    Project   = var.project_name
  }, var.additional_tags)
}

module "networking" {
  source                      = "./cloud-infra/networking"
  project_name                = var.project_name
  kubernetes_api_allowed_cidr = var.kubernetes_api_allowed_cidr
  talos_api_allowed_cidr      = var.talos_api_allowed_cidr
  availability_zones          = var.availability_zones
  vpc_cidr                    = var.vpc_cidr
  tags                        = local.tags
}

data "aws_caller_identity" "current" {}

locals {
  # The cluster publishes its OpenID Connect discovery documents to this
  # bucket, and names the bucket's URL as the issuer of its service account
  # tokens - which is what lets AWS verify them and makes IRSA work without
  # EKS. The bucket itself is created by the bootstrap module; the name is
  # decided here because the API server's issuer flag has to carry it, and
  # that flag is baked into the machine config rendered below.
  #
  # The account ID is in the name because S3 bucket names are global, and a
  # project name on its own would collide with the same project in someone
  # else's account. Virtual-hosted style, so the name must stay
  # DNS-compatible: project_name is already constrained to that.
  oidc_bucket     = "${var.project_name}-oidc-${data.aws_caller_identity.current.account_id}"
  oidc_issuer_url = "https://${local.oidc_bucket}.s3.${var.region}.amazonaws.com"
}

module "talos_config" {
  source                 = "./talos/config"
  project_name           = var.project_name
  load_balancer_dns      = module.networking.load_balancer_dns
  service_account_issuer = local.oidc_issuer_url
  kubernetes_version     = var.kubernetes_version
  talos_version          = var.talos_version
  pod_cidr               = var.pod_cidr
  hardening              = var.hardening
  config_output_path     = var.config_output_path
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
  tags                            = local.tags
}

# Bootstrap only has to reach one control plane node, so this takes one.
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

locals {
  control_plane = data.aws_instances.control_plane_instances

  # AWS does not promise an order for the instances this data source returns,
  # so `public_ips[0]` can name a different node between refreshes. The Talos
  # bootstrap resource takes that address as an input and replaces itself when
  # it changes, which would re-run the bootstrap against a cluster that is
  # already bootstrapped. Picking the position of the lowest instance ID makes
  # the choice deterministic while still indexing both lists identically, so
  # the public/private pairing above is preserved.
  bootstrap_index = index(local.control_plane.ids, sort(local.control_plane.ids)[0])
}

module "talos_bootstrap" {
  source               = "./talos/bootstrap"
  client_configuration = module.talos_config.client_configuration
  public_ip            = local.control_plane.public_ips[local.bootstrap_index]
  private_ip           = local.control_plane.private_ips[local.bootstrap_index]
  config_output_path   = var.config_output_path
}

locals {
  # The admin credentials again, split into the fields a client needs, so the
  # bootstrap module can read the cluster's OIDC discovery documents straight
  # from the API server over mutual TLS. Decomposed the same way
  # `examples/full` decomposes it for the kubernetes provider.
  kubeconfig = yamldecode(module.talos_bootstrap.kubeconfig)

  kubernetes_client_configuration = {
    host               = local.kubeconfig["clusters"][0]["cluster"]["server"]
    ca_certificate     = base64decode(local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
    client_certificate = base64decode(local.kubeconfig["users"][0]["user"]["client-certificate-data"])
    client_key         = base64decode(local.kubeconfig["users"][0]["user"]["client-key-data"])
  }
}
