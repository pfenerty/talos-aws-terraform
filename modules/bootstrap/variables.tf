variable "cluster" {
  description = "Everything this module needs to know about the cluster it is bootstrapping. Pass the cluster module's bootstrap_inputs output straight through."
  sensitive   = true
  type = object({
    project_name       = string
    region             = string
    pod_cidr           = string
    talos_version      = string
    kubernetes_version = string
    cluster_endpoint   = string
    load_balancer_dns  = string
    client_configuration = object({
      ca_certificate     = string
      client_certificate = string
      client_key         = string
    })
    control_plane_public_ips        = list(string)
    control_plane_private_ips       = list(string)
    worker_private_ips              = list(string)
    node_count                      = number
    worker_instance_profile_name    = string
    worker_iam_role_arn             = string
    worker_ami_id                   = string
    worker_architecture             = string
    karpenter_worker_machine_config = string

    # IRSA. The bucket is created here but named by the cluster module,
    # because the issuer URL built from it is in the API server's machine
    # config, and the cluster module is what renders that.
    oidc_bucket     = string
    oidc_issuer_url = string

    # Facts the cloud controller manager is given in its cloud config, now
    # that a pod cannot read them from the instance metadata service.
    vpc_id    = string
    subnet_id = string

    # Admin credentials for the Kubernetes API, used to read the cluster's
    # own OIDC discovery documents. The endpoints are not anonymous.
    kubernetes_client_configuration = object({
      ca_certificate     = string
      client_certificate = string
      client_key         = string
    })

    tags = map(string)
  })
}

variable "flux" {
  description = "Flux bootstrap. Disabled by default; when enabled, Flux is bootstrapped from the git repository described here and takes ownership of everything in the cluster, Cilium's day-2 configuration included."
  sensitive   = true
  type = object({
    enabled    = bool
    git_url    = string
    git_branch = string
    ssh_key    = string
  })
  default = {
    enabled    = false
    git_url    = ""
    git_branch = ""
    ssh_key    = ""
  }

  validation {
    condition     = !(var.flux.enabled && var.flux.git_url == "")
    error_message = "If Flux post install is enabled, you must provide a git url to bootstrap flux."
  }

  validation {
    condition     = !(var.flux.enabled && var.flux.git_branch == "")
    error_message = "If Flux post install is enabled, you must provide a git branch to bootstrap flux."
  }

  validation {
    condition     = !(var.flux.enabled && var.flux.ssh_key == "")
    error_message = "If Flux post install is enabled, you must provide a git ssh key to bootstrap flux."
  }
}

variable "extras" {
  description = "Terraform-managed AWS resources that the Flux bootstrap repository consumes. They publish their credentials into flux-system secrets, so they require Flux."
  type = object({
    ebs       = bool
    karpenter = bool
  })
  default = {
    ebs       = false
    karpenter = false
  }
}

variable "karpenter" {
  type = object({
    capacity_types = optional(list(string), ["spot", "on-demand"])
  })
  default     = {}
  description = <<-EOT
    Karpenter provisioning policy, published into the karpenter-config secret
    for the NodePool in the Flux bootstrap repository to read.

    `capacity_types` is the list of EC2 purchase options the NodePool may
    provision, in no particular order - Karpenter's own price-capacity-optimized
    strategy decides between them, and listing spot first does not prefer it.
    The default allows both, which is what makes elastic capacity cost a
    fraction of the baseline; drop to ["on-demand"] for workloads that cannot
    absorb a two-minute interruption notice.

    Spot is safe to allow here by construction: this module creates the
    interruption queue and the EventBridge rules that feed it, so Karpenter
    sees the reclamation notice and drains the node rather than losing it.

    This only sets what Terraform publishes. The NodePool has to read it -
    see "Node autoscaling" in the README for the valuesFrom entry.
  EOT

  validation {
    condition     = length(var.karpenter.capacity_types) > 0
    error_message = "karpenter.capacity_types must name at least one of spot or on-demand."
  }

  validation {
    condition     = length(setsubtract(var.karpenter.capacity_types, ["spot", "on-demand"])) == 0
    error_message = "karpenter.capacity_types may only contain \"spot\" and \"on-demand\"."
  }
}

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io
variable "cilium_bootstrap_version" {
  type        = string
  default     = "1.20.2"
  description = "Cilium chart version installed to get the cluster to Ready. Changing it affects new clusters only: on an existing cluster Cilium belongs to Flux, and this module deliberately stops reconciling the release after creating it."
}

variable "hubble_ca_validity_hours" {
  type        = number
  default     = 12
  description = "Lifetime of the self-signed Hubble trust anchor, in hours. The default of 12 is carried over from before this was configurable and is almost certainly too short for a CA that cert-manager issues from - raise it, or move the trust anchor to cert-manager entirely."
}

variable "cluster_health_timeout" {
  type        = string
  default     = "10m"
  description = "How long to wait for the cluster to report healthy before giving up. This is a ceiling, not a delay: the check returns as soon as the cluster is ready. Terraform re-reads the health check on refresh, so this also bounds how long a plan blocks when the cluster is unreachable."

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.cluster_health_timeout))
    error_message = "cluster_health_timeout must be a duration of seconds, minutes or hours, for example \"10m\" or \"600s\"."
  }
}
