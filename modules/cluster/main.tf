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
  instance_refresh                = var.machine_config_updates.instance_refresh
  tags                            = local.tags
}

# Where the node addresses come from. The autoscaling groups decide what
# exists, so the bootstrap target, the nodes a config change is applied to and
# the health check's node list are all read back from AWS rather than known
# up front.
#
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
  workers       = data.aws_instances.worker_instances

  # AWS does not promise an order for the instances these data sources return,
  # so `public_ips[0]` can name a different node between refreshes. Anything
  # that takes a node address as an input then looks changed when nothing has:
  # the bootstrap resource would re-run against an already-bootstrapped
  # cluster, and each configuration apply would move to a different machine.
  #
  # Re-ordering by instance ID makes the choice deterministic. The positions
  # are computed first and then used to index every list, so the public and
  # private addresses stay paired - which independently sorting each list
  # would quietly break.
  control_plane_order = [for id in sort(local.control_plane.ids) : index(local.control_plane.ids, id)]
  worker_order        = [for id in sort(local.workers.ids) : index(local.workers.ids, id)]

  control_plane_public_ips  = [for position in local.control_plane_order : local.control_plane.public_ips[position]]
  control_plane_private_ips = [for position in local.control_plane_order : local.control_plane.private_ips[position]]
  worker_private_ips        = [for position in local.worker_order : local.workers.private_ips[position]]
}

# Bootstrap only has to reach one control plane node, and the lowest instance
# ID is as good a choice as any as long as it is the same one every time.
module "talos_bootstrap" {
  source               = "./talos/bootstrap"
  client_configuration = module.talos_config.client_configuration
  public_ip            = local.control_plane_public_ips[0]
  private_ip           = local.control_plane_private_ips[0]
  config_output_path   = var.config_output_path
}

# The machine config reaches running nodes here, and new nodes through launch
# template user data. Neither channel covers both populations on its own; see
# ./talos/apply for why, and "Machine config updates" in the README for what
# that means in practice.
#
# These run after the bootstrap so that the Talos API is known to be up and
# answering on the control plane before anything is applied to it. On a first
# apply they are no-ops: the nodes booted from this very configuration.
module "talos_apply_control_plane" {
  count  = var.machine_config_updates.apply_to_running_nodes ? 1 : 0
  source = "./talos/apply"

  client_configuration  = module.talos_config.client_configuration
  machine_configuration = module.talos_config.control_plane_machine_config
  node_count            = var.control_plane_nodes
  nodes                 = local.control_plane_private_ips
  endpoints             = local.control_plane_public_ips
  apply_mode            = var.machine_config_updates.apply_mode

  depends_on = [module.talos_bootstrap]
}

# Workers carry only the internal security group, so their Talos API is not
# reachable from outside the VPC. They are addressed through a control plane
# node instead, which routes to them over the node-to-node rule - the same
# thing `talosctl -e <control plane> -n <worker>` does.
module "talos_apply_workers" {
  count  = var.machine_config_updates.apply_to_running_nodes ? 1 : 0
  source = "./talos/apply"

  client_configuration  = module.talos_config.client_configuration
  machine_configuration = module.talos_config.worker_machine_config
  node_count            = var.worker_nodes_min
  nodes                 = local.worker_private_ips
  endpoints             = [local.control_plane_public_ips[0]]
  apply_mode            = var.machine_config_updates.apply_mode

  depends_on = [module.talos_bootstrap]
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
