variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to create infastructure in"
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "Named profile from the shared AWS config to authenticate with. Left null, the standard credential chain is used (environment variables, SSO, instance or container role)."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource this module creates, on top of the cluster, ManagedBy and Project tags."
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

variable "project_name" {
  type        = string
  default     = "talos-cluster"
  description = "Project name. Used as the prefix for every AWS resource name, as the Talos cluster name, and verbatim as the load balancer and target group name - which is what the constraints below come from."

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

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io
variable "cilium_version" {
  type        = string
  default     = "1.20.2"
  description = "Version of Cilium to deploy"
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod subnet CIDR. Set on the Talos machine config and reused as Cilium's strict-mode egress CIDR so the two cannot drift apart."
}

variable "cluster_ready_wait" {
  type        = string
  default     = "90s"
  description = "How long to wait after bootstrap before post-install starts using the Kubernetes API. A fixed delay rather than a readiness check; raise it if post-install fails against an API server that is not answering yet."

  validation {
    condition     = can(regex("^[0-9]+(ns|us|ms|s|m|h)$", var.cluster_ready_wait))
    error_message = "cluster_ready_wait must be a Go duration string, for example \"90s\" or \"3m\"."
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
  description = "What to install once the cluster is up. Flux bootstraps from the git repository described here; the extras are Terraform-managed AWS resources that the Flux bootstrap repository consumes, so they require Flux."

  validation {
    condition     = !(var.post_install.flux.enabled && var.post_install.flux.git_url == "")
    error_message = "If Flux post install is enabled, you must provide a git url to bootstrap flux."
  }

  validation {
    condition     = !(var.post_install.flux.enabled && var.post_install.flux.git_branch == "")
    error_message = "If Flux post install is enabled, you must provide a git branch to bootstrap flux."
  }

  validation {
    condition     = !(var.post_install.flux.enabled && var.post_install.flux.ssh_key == "")
    error_message = "If Flux post install is enabled, you must provide a git ssh key to bootstrap flux."
  }

  validation {
    condition     = !(!var.post_install.flux.enabled && (var.post_install.extras.ebs || var.post_install.extras.karpenter))
    error_message = "Post install extras are enabled but Flux post install is not. The extras are designed for Flux; enable Flux post install if you want to use them."
  }
}
