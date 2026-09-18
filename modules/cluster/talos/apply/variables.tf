variable "client_configuration" {
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  sensitive   = true
  description = "Talos client certificates produced by the config module."
}

variable "machine_configuration" {
  type        = string
  sensitive   = true
  description = "Rendered Talos machine config for this group of nodes. The same string the launch template carries as user data, so the two channels cannot deliver different configurations."
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the group, taken from its configured size rather than from the instances found. Terraform resolves a resource's count at plan time, and instance addresses are only known once the autoscaling groups have applied."
}

variable "nodes" {
  type        = list(string)
  description = "Private addresses of the nodes to apply to, which is how Talos identifies a node. Must be ordered stably - by instance ID - so that an index names the same machine between plans."
}

variable "endpoints" {
  type        = list(string)
  description = "Talos API addresses to reach the nodes through, indexed alongside `nodes` and wrapped if shorter: a single-element list sends every node's apply through one endpoint, which is how workers are reached."
}

variable "apply_mode" {
  type        = string
  description = "How Talos applies the configuration. `staged_if_needing_reboot` dry-runs the change and stages it for the next boot if it would need a reboot, applying it immediately otherwise. `auto` reboots where a reboot is required, which Terraform has no way to serialise across the group."

  validation {
    condition     = contains(["auto", "no_reboot", "reboot", "staged", "staged_if_needing_reboot", "try"], var.apply_mode)
    error_message = "apply_mode must be one of auto, no_reboot, reboot, staged, staged_if_needing_reboot or try."
  }
}
