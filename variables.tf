variable "project_name" {
  type        = string
  description = "Project name. Used as the prefix for every AWS resource name, as the Talos cluster name, and verbatim as the load balancer and target group name - which is what the constraints below come from. Required: every name this module creates derives from it, and several of them are account-global."

  # The load balancer and target group take this name verbatim, and AWS is
  # stricter about those than about anything else here: 32 characters,
  # alphanumeric and hyphens only, no hyphen at either end. An underscore
  # anywhere in the name failed at apply time rather than at plan time.
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", var.project_name))
    error_message = "project_name must be 1-32 alphanumeric characters and hyphens, and may not start or end with a hyphen: it is used verbatim as the load balancer and target group name."
  }

  validation {
    condition     = !startswith(var.project_name, "internal-")
    error_message = "project_name must not start with \"internal-\": AWS reserves that prefix for internal load balancers."
  }
}

variable "region" {
  type        = string
  description = "AWS region the cluster runs in. This selects the Talos AMI and is handed to Karpenter; it does not configure the AWS provider, which is the caller's to set."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource this module creates, on top of the cluster, ManagedBy and Project tags."
}

variable "availability_zones" {
  description = "Availability Zones to create subnets in. Null means every zone the region currently reports, which is convenient but means the subnet layout changes if AWS adds a zone; pin it for anything long-lived. The availability_zones output reports what was used."
  type        = list(string)
  default     = null
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Subnets are carved out of it with a /8 offset per Availability Zone, so it needs to be large enough for one /24 per zone."
  type        = string
  default     = "172.31.0.0/16"
}

variable "talos_api_allowed_cidr" {
  description = "CIDR allowed to reach the Talos API on port 50000. The default is open to the internet, which is what makes `terraform apply` work from anywhere but is the wrong setting for anything you care about: the Talos API administers the machines themselves. Narrow it to your own address."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.talos_api_allowed_cidr))
    error_message = "talos_api_allowed_cidr must be a valid IPv4 CIDR block, for example \"203.0.113.4/32\"."
  }
}

variable "kubernetes_api_allowed_cidr" {
  description = "CIDR allowed to reach the Kubernetes API on port 6443. Open to the internet by default; narrow it to your own address where you can."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.kubernetes_api_allowed_cidr))
    error_message = "kubernetes_api_allowed_cidr must be a valid IPv4 CIDR block, for example \"203.0.113.4/32\"."
  }
}

variable "control_plane_nodes" {
  type        = number
  default     = 1
  description = "Number of control plane nodes. etcd needs an odd number to hold quorum; 1 is fine for a throwaway cluster but has no redundancy, and an instance refresh will briefly take the API server away."

  validation {
    condition     = var.control_plane_nodes > 0 && var.control_plane_nodes % 2 == 1
    error_message = "control_plane_nodes must be a positive odd number, so that etcd can form a quorum."
  }
}

variable "control_plane_node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "AWS EC2 instance type for control plane nodes"
}

variable "worker_nodes_min" {
  type        = number
  default     = 1
  description = "Size the worker autoscaling group is created at. Nothing scales this group: it is the static baseline that Karpenter itself and the rest of the cluster add-ons run on, and Karpenter provisions everything above it."

  validation {
    condition     = var.worker_nodes_min > 0
    error_message = "worker_nodes_min must be at least 1: the cluster add-ons, Karpenter included, have nowhere to run otherwise."
  }
}

variable "worker_nodes_max" {
  type        = number
  default     = 5
  description = "Ceiling on the worker autoscaling group. Only reached by scaling the group by hand; elastic capacity comes from Karpenter instead. Must leave at least one instance of headroom above worker_nodes_min, which is what a rolling instance refresh launches its replacement into."

  validation {
    condition     = var.worker_nodes_max > var.worker_nodes_min
    error_message = "worker_nodes_max must be greater than worker_nodes_min: an instance refresh launches a replacement before terminating a node, and needs one instance of headroom to do it."
  }
}

variable "worker_node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "AWS EC2 instance type for worker nodes"
}

# renovate: datasource=github-releases depName=siderolabs/talos
variable "talos_version" {
  type        = string
  default     = "v1.14.1"
  description = "Talos Linux version"
}

# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
variable "kubernetes_version" {
  type        = string
  default     = "1.37.0"
  description = "Kubernetes version"
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod subnet CIDR. Set on the Talos machine config and reused as Cilium's strict-mode egress CIDR so the two cannot drift apart."
}

variable "hardening" {
  type = object({
    enabled                        = optional(bool, false)
    pod_security_enforce           = optional(string, "restricted")
    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])
    kubelet_serving_certificates   = optional(bool, false)
  })
  default     = {}
  description = "Machine config hardening, off by default because it changes what the cluster will admit. `enabled` turns on a real API server audit policy and Pod Security Admission enforcing the standard named below. It is the machine config half of a hardening baseline and not the whole of one: docs/hardening.md sets out what it covers, what Talos already does without it, and what has to be enforced in the Flux repository or the AWS layer instead. `kubelet_serving_certificates` makes the kubelet bootstrap a CA-signed serving certificate rather than self-signing one, and requires a CSR approver running in the cluster - a Flux dependency this module cannot install, and without which `kubectl logs` and `exec` stop working."
}

variable "config_output_path" {
  type        = string
  default     = null
  description = "Directory to write the generated kubeconfig, talosconfig and machine config files into. Null, the default, writes nothing: the same files are available as outputs, and a module that writes into the caller's directory collides with itself when instantiated more than once. The files carry cluster credentials and are written mode 0600."
}

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io
variable "cilium_bootstrap_version" {
  type        = string
  default     = "1.20.2"
  description = "Cilium chart version installed to get the cluster to Ready. Changing it affects new clusters only: on an existing cluster Cilium belongs to Flux, and the bootstrap module deliberately stops reconciling the release after creating it."
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

variable "post_install" {
  type = object({
    flux = object({
      enabled    = bool
      git_url    = string
      git_branch = string
      ssh_key    = string
    })
    extras = object({
      ebs       = bool
      karpenter = bool
    })
  })
  default = {
    flux = {
      enabled    = false
      git_url    = ""
      git_branch = ""
      ssh_key    = ""
    }
    extras = {
      ebs       = false
      karpenter = false
    }
  }
  sensitive   = true
  description = "What to install once the cluster is up. Flux bootstraps from the git repository described here; the extras are Terraform-managed AWS resources that the Flux bootstrap repository consumes, so they require Flux. Cilium is not listed: it is not optional, because the cluster cannot reach a healthy state without a CNI."

  validation {
    condition     = !(!var.post_install.flux.enabled && (var.post_install.extras.ebs || var.post_install.extras.karpenter))
    error_message = "Post install extras are enabled but Flux post install is not. The extras are designed for Flux; enable Flux post install if you want to use them."
  }
}

variable "machine_config_updates" {
  type = object({
    apply_to_running_nodes = optional(bool, true)
    apply_mode             = optional(string, "staged_if_needing_reboot")
    instance_refresh       = optional(bool, false)
  })
  default     = {}
  description = <<-EOT
    How a machine config change reaches nodes that are already running. The
    machine config is launch template user data, which Talos reads once at
    first boot, so on its own it only ever reaches a node by replacing it.

    `apply_to_running_nodes` applies the rendered config to the existing
    control plane and baseline worker nodes over the Talos API, which is what
    `talosctl apply-config` does, so a config edit reconfigures the cluster
    rather than rebuilding it. User data is still what a newly launched node
    reads, so nodes the autoscaling groups or Karpenter bring up later come
    up configured without anything to run by hand.

    `apply_mode` is how Talos applies it. The default dry-runs the change and
    stages it for the next boot if it would need a reboot, applying it
    immediately otherwise - which is what keeps a config edit from rebooting
    every control plane node at once, since Terraform has no way to serialise
    that. `auto` reboots where Talos says a reboot is required.

    `instance_refresh` rolls both autoscaling groups whenever their launch
    template changes, which is the old behaviour and the only way an AMI
    change reaches existing nodes. Off by default: with it on, a one-line
    config edit replaces every node in the cluster.
  EOT

  validation {
    condition     = contains(["auto", "no_reboot", "reboot", "staged", "staged_if_needing_reboot", "try"], var.machine_config_updates.apply_mode)
    error_message = "machine_config_updates.apply_mode must be one of auto, no_reboot, reboot, staged, staged_if_needing_reboot or try."
  }
}

variable "kubernetes_talos_api_access" {
  type = object({
    enabled    = optional(bool, false)
    roles      = optional(list(string), ["os:admin"])
    namespaces = optional(list(string), ["system-upgrade"])
  })
  default     = {}
  description = <<-EOT
    Lets service accounts in the named Kubernetes namespaces obtain Talos API
    credentials carrying the named roles. Off by default.

    This is how an in-cluster upgrade controller - tuppr, in the Flux bootstrap
    repository - calls the Talos upgrade API on each node, which is what makes
    a Talos version bump a change to a manifest rather than a fleet
    replacement or a run of `talosctl` by hand.

    It is deliberately not part of `hardening`, because it is the opposite of
    hardening. `os:admin` is root on the machine as far as Talos is concerned:
    a pod holding it can read the machine config, certificate keys included,
    and replace it. That is a real widening of the cluster's trust boundary,
    and docs/hardening.md sets out what it buys and what it costs.
  EOT
}
