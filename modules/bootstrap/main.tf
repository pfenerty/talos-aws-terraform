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

# The sync path is the project name, not a generated one. Flux bootstrap only
# ever writes `<path>/flux-system`, while the Kustomizations that describe what
# the cluster actually runs are committed to `<path>` in the bootstrap
# repository beforehand - which is only possible if the path is known before
# the apply. A generated path also orphans a directory on every destroy and
# recreate, and gives the repository no way to tell one cluster from another.
#
# project_name is already constrained to what a load balancer name allows, so
# it is a valid path segment.
resource "flux_bootstrap_git" "this" {
  count = var.flux.enabled ? 1 : 0

  # The cloud controller manager is the first thing Flux installs that needs
  # AWS credentials, so its role, its cloud config and the OIDC documents AWS
  # verifies its token against all have to exist before Flux starts.
  depends_on = [
    data.talos_cluster_health.this,
    module.cloud_controller,
  ]

  path = "clusters/${var.cluster.project_name}"

  kustomization_override = file("${path.module}/flux.patch.yaml")
}

# Every component in the cluster that talks to AWS does it with a role it
# assumes using a projected service account token - the cloud controller
# manager, the EBS CSI driver and Karpenter alike. None of them holds a key
# pair, and none of them can fall back to the node's instance profile: the
# launch templates set an IMDS hop limit of 1, which a pod cannot cross.
#
# This is the piece that makes that possible off EKS: the cluster's OIDC
# discovery documents, published to S3 where AWS can read them, and registered
# as an IAM identity provider.
module "oidc" {
  source = "./oidc"

  depends_on = [data.talos_cluster_health.this]

  bucket_name                     = var.cluster.oidc_bucket
  issuer_url                      = var.cluster.oidc_issuer_url
  cluster_endpoint                = var.cluster.cluster_endpoint
  kubernetes_client_configuration = var.cluster.kubernetes_client_configuration
  tags                            = var.cluster.tags
}

locals {
  # Where each pod's projected service account token is mounted. Terraform
  # writes it into the config the AWS SDK reads; the Flux bootstrap repository
  # mounts the token there. The two have to agree, and nothing checks that
  # they do - a mismatch shows up as an AssumeRoleWithWebIdentity failure in
  # the workload's logs.
  irsa_token_path = "/var/run/secrets/aws/token"
}

# The cloud controller manager, which is installed by Flux and is the first
# thing in the cluster to need AWS credentials: until it has run, every node
# carries the uninitialized taint.
module "cloud_controller" {
  count = var.flux.enabled ? 1 : 0

  source = "./cloud-controller"

  project_name = var.cluster.project_name
  region       = var.cluster.region
  vpc_id       = var.cluster.vpc_id
  subnet_id    = var.cluster.subnet_id
  token_path   = local.irsa_token_path
  oidc         = module.oidc
  tags         = var.cluster.tags
}

module "ebs" {
  count = var.extras.ebs ? 1 : 0

  source         = "./ebs"
  project_name   = var.cluster.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = var.cluster.region
  token_path     = local.irsa_token_path
  oidc           = module.oidc
  tags           = var.cluster.tags
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
  node_architecture          = var.cluster.worker_architecture
  node_user_data             = var.cluster.karpenter_worker_machine_config
  capacity_types             = var.karpenter.capacity_types
  token_path                 = local.irsa_token_path
  oidc                       = module.oidc
  tags                       = var.cluster.tags

  # The karpenter-config secret goes in flux-system, which does not exist
  # until Flux has been bootstrapped.
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

# The versions the cluster is meant to be running, for the upgrade controller
# in the Flux bootstrap repository to converge on.
#
# Read differently from every other object here. The others are pulled into a
# HelmRelease through valuesFrom, but tuppr's chart templates only the
# controller - there is no HelmRelease to hang a TalosUpgrade off - so the
# upgrade resources are plain manifests in the repository and Flux substitutes
# these values into them with postBuild.substituteFrom. That is a plain string
# replace, which is exactly why karpenter-config could not use it for a
# multi-line machine config; a version is a single-line scalar, so it can.
#
# A ConfigMap rather than a Secret because a version number is not a
# credential, and substituteFrom reads either.
#
# Terraform owns these values because var.talos_version already has to exist
# here to select the AMI. Restating them in the Flux repository would mean two
# sources of truth for one upgrade, and a window where the version the nodes
# boot on and the version the controller converges to disagree.
resource "kubernetes_config_map_v1" "cluster_versions" {
  count = var.flux.enabled ? 1 : 0

  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "cluster-versions"
    namespace = "flux-system"
  }

  # Both carry a leading `v`, because both upgrade resources validate their
  # version against `^v[0-9]+\.[0-9]+\.[0-9]+...` and reject anything else.
  # talos_version already has one; kubernetes_version does not, because the
  # Talos machine config wants it without. Normalising here rather than in the
  # manifest keeps the two substitutions symmetric and removes the one place
  # the `v` could be forgotten - the admission webhook would catch it, but as
  # a rejected manifest in a Flux reconcile rather than at plan.
  data = {
    talos_version      = startswith(var.cluster.talos_version, "v") ? var.cluster.talos_version : "v${var.cluster.talos_version}"
    kubernetes_version = startswith(var.cluster.kubernetes_version, "v") ? var.cluster.kubernetes_version : "v${var.cluster.kubernetes_version}"
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
