data "aws_caller_identity" "current" {}

# Cilium first, and before the health check below. Talos runs with `cni: none`
# and kube-proxy disabled, so until a CNI exists CoreDNS cannot start and every
# node stays NotReady - which is exactly what talos_cluster_health waits for.
# Gating Cilium on the health check, as this used to, waits for the thing that
# Cilium is what produces.
#
# Cilium can install into that cluster where nothing else can: its agent,
# envoy and operator workloads all run on the host network, the DaemonSets
# tolerate everything, and the operator tolerates the not-ready and
# cloudprovider-uninitialized taints specifically. The agents reach the API
# server through KubePrism on localhost:7445 rather than through a Service,
# so they need neither kube-proxy nor DNS.
module "cilium" {
  source                   = "./cilium"
  cilium_version           = var.cilium_bootstrap_version
  operator_replicas        = min(2, var.cluster.node_count)
  hubble_ca_validity_hours = var.hubble_ca_validity_hours
}

# Blocks until the cluster reports healthy - etcd quorum, kubelet up on every
# node, control plane components live - rather than waiting out a fixed delay
# and hoping. This is the Talos provider's own readiness check, so it knows
# what healthy means; a timer did not.
data "talos_cluster_health" "this" {
  depends_on = [module.cilium]

  client_configuration = var.cluster.client_configuration
  control_plane_nodes  = var.cluster.control_plane_private_ips
  worker_nodes         = var.cluster.worker_private_ips

  # Node addresses are private, so the client reaches them through a control
  # plane node's public address.
  endpoints = var.cluster.control_plane_public_ips

  timeouts = {
    read = var.cluster_health_timeout
  }
}

resource "random_uuid" "cluster_flux_id" {}

resource "flux_bootstrap_git" "this" {
  count = var.flux.enabled ? 1 : 0

  depends_on = [data.talos_cluster_health.this]

  path = "clusters/${random_uuid.cluster_flux_id.result}"

  kustomization_override = file("${path.module}/flux.patch.yaml")
}

module "ebs" {
  count = var.extras.ebs ? 1 : 0

  source         = "./ebs"
  project_name   = var.cluster.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
}

module "karpenter" {
  count  = var.extras.karpenter ? 1 : 0
  source = "./karpenter"

  project_name   = var.cluster.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = var.cluster.region

  cluster_endpoint           = var.cluster.cluster_endpoint
  node_instance_profile_name = var.cluster.worker_instance_profile_name
  node_iam_role_arn          = var.cluster.worker_iam_role_arn
  node_ami_id                = var.cluster.worker_ami_id
  node_user_data             = var.cluster.karpenter_worker_machine_config

  depends_on = [flux_bootstrap_git.this]
}

resource "kubernetes_secret_v1" "aws_lb_config" {
  count = var.flux.enabled ? 1 : 0

  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "aws-loadbalancer-config"
    namespace = "flux-system"
  }

  data = {
    dns_name = var.cluster.load_balancer_dns
  }
}

# Values the Flux bootstrap repository's Cilium HelmRelease reads through
# valuesFrom, in the same shape as karpenter-config. Flux owns Cilium's
# day-2 configuration, so it needs the pod CIDR that the Talos machine
# config was generated with - the strict-mode egress CIDR has to match it
# exactly or encryption silently stops covering pod traffic.
resource "kubernetes_secret_v1" "cilium_config" {
  count = var.flux.enabled ? 1 : 0

  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "cilium-config"
    namespace = "flux-system"
  }

  data = {
    pod-cidr = var.cluster.pod_cidr
  }
}
