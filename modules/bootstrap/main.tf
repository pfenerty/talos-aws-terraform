data "aws_caller_identity" "current" {}

# Waits for the Kubernetes API to answer through the load balancer before
# anything talks to it. Nothing earlier in the apply does: the kubeconfig comes
# from the Talos API on port 50000, which is up as soon as the machine boots,
# and talos_machine_bootstrap returns once etcd has been told to bootstrap, not
# once kube-apiserver is serving. kube-apiserver then needs a minute or two to
# start, and the NLB needs several health checks to pass before it forwards a
# connection. The helm and kubernetes providers dial once and do not retry, so
# without this the first thing to touch the cluster fails with
# `Kubernetes cluster unreachable ... i/o timeout` on a cluster that is
# perfectly healthy a minute later.
#
# /readyz rather than /livez: it only succeeds once the API server has finished
# its post-start hooks, RBAC bootstrap included, which is what an install needs.
# Read over mutual TLS with the admin certificate, as the OIDC documents are,
# so it does not depend on anonymous access to health endpoints being enabled.
#
# Retries cover connection errors and 5xx, which is everything the API server
# and the load balancer do while starting. The budget is about seven minutes
# worst case; a healthy cluster answers on the first attempt.
data "http" "api_ready" {
  url             = "${var.cluster.cluster_endpoint}/readyz"
  ca_cert_pem     = var.cluster.kubernetes_client_configuration.ca_certificate
  client_cert_pem = var.cluster.kubernetes_client_configuration.client_certificate
  client_key_pem  = var.cluster.kubernetes_client_configuration.client_key

  request_timeout_ms = 8000

  retry {
    attempts     = 30
    min_delay_ms = 2000
    max_delay_ms = 6000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The Kubernetes API answered ${self.status_code} on /readyz through the load balancer. The control plane is not healthy; check `talosctl containers -k` and the kube-apiserver log on a control plane node."
    }
  }
}

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
  depends_on               = [data.http.api_ready]
  cilium_version           = var.cilium_bootstrap_version
  operator_replicas        = min(2, var.cluster.node_count)
  hubble_ca_validity_hours = var.hubble_ca_validity_hours
}

# The kubelet serving certificate approver, for hardening.kubelet_serving_certificates.
# After Cilium, because it is a pod and needs a node that can run one. The
# health check below waits for it: with serverTLSBootstrap on, a control plane
# kubelet cannot answer Talos's static pod status query until its serving
# request is approved, so the cluster does not report healthy without it.
module "kubelet_csr_approver" {
  count = var.kubelet_csr_approver_enabled ? 1 : 0

  source        = "./csr-approver"
  depends_on    = [module.cilium]
  chart_version = var.kubelet_csr_approver_version
  region        = var.cluster.region
  vpc_cidr      = var.cluster.vpc_cidr
  replicas      = min(2, var.cluster.node_count)
}

# Blocks until the cluster reports healthy - etcd quorum, kubelet up on every
# node, control plane components live - rather than waiting out a fixed delay
# and hoping. This is the Talos provider's own readiness check, so it knows
# what healthy means; a timer did not.
data "talos_cluster_health" "this" {
  depends_on = [module.cilium, module.kubelet_csr_approver]

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
