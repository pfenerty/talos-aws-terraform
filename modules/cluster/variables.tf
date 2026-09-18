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

variable "config_output_path" {
  type        = string
  default     = null
  description = "Directory to write the generated kubeconfig, talosconfig and machine config files into. Null, the default, writes nothing: the same files are available as outputs, and a module that writes into the caller's directory collides with itself when instantiated more than once. The files carry cluster credentials and are written mode 0600."
}

variable "hardening" {
  type = object({
    enabled                        = optional(bool, false)
    pod_security_enforce           = optional(string, "restricted")
    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])
    kubelet_serving_certificates   = optional(bool, false)
  })
  default     = {}
  description = "Machine config hardening, off by default because it changes what the cluster will admit. Passed through to the Talos config module; see docs/hardening.md for what it covers, what it deliberately leaves alone, and what has to be enforced outside the machine config. kubelet_serving_certificates additionally requires a CSR approver deployed by Flux; see the doc before enabling it."
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
    namespaces = optional(list(string), ["tuppr-system"])
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

    A namespace is the only granularity Talos offers here - there is no
    service account or pod selector - so the namespace named must hold
    nothing but the controller, and it must match the controller's release
    namespace exactly or every upgrade fails at the first node. The default
    is a dedicated `tuppr-system` rather than the conventional
    `system-upgrade`, which other operators also install into.
  EOT
}
