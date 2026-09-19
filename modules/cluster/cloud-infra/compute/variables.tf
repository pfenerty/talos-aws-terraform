variable "project_name" {
  type        = string
  description = "Project name, used to name and tag the compute resources."
}

variable "region" {
  type        = string
  description = "AWS region, used to select the Talos AMI published for it."
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version, used to select the matching AMI."
}

variable "subnets" {
  type        = list(string)
  description = "Subnets the autoscaling groups launch instances into."
}

variable "control_plane_instance_type" {
  type        = string
  description = "EC2 instance type for control plane nodes."
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 instance type for the baseline worker nodes."
}

variable "control_plane_nodes" {
  type        = number
  description = "Size of the control plane autoscaling group. The group's max_size is one higher, so an instance refresh can launch a replacement before terminating a node."
}

variable "worker_nodes_min" {
  type        = number
  description = "Size the worker autoscaling group is created at and stays at; Karpenter provisions capacity above it."
}

variable "worker_nodes_max" {
  type        = number
  description = "Ceiling on the worker autoscaling group. Must exceed worker_nodes_min to leave an instance refresh room to work."
}

variable "control_plane_machine_config" {
  type        = string
  sensitive   = true
  description = "Talos control plane machine config, applied as launch template user data."
}

variable "worker_machine_config" {
  type        = string
  sensitive   = true
  description = "Talos worker machine config, applied as launch template user data."
}

variable "control_plane_security_group_id" {
  type        = string
  description = "Security group granting external access to the Kubernetes and Talos APIs."
}

variable "internal_security_group_id" {
  type        = string
  description = "Security group allowing node-to-node traffic and outbound access."
}

variable "load_balancer_target_group_arn" {
  type        = string
  description = "Target group the control plane autoscaling group registers into."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource, and propagated to the instances the autoscaling groups launch. Carries the kubernetes.io/cluster tag the AWS cloud controller manager looks for."
}

variable "instance_refresh" {
  type        = bool
  default     = false
  description = "Roll both autoscaling groups whenever their launch template changes. Off by default: the machine config is launch template user data, so this would replace every node to deliver a config edit, and the cluster module applies config changes to running nodes over the Talos API instead. Turning it on restores immutable-node behaviour, at the cost of an etcd membership change per control plane node per config change."
}

variable "control_plane_architecture" {
  type        = string
  default     = "amd64"
  description = "CPU architecture of the control plane AMI. Must match the architecture of control_plane_instance_type."

  validation {
    condition     = contains(["amd64", "arm64"], var.control_plane_architecture)
    error_message = "control_plane_architecture must be amd64 or arm64: those are the architectures Sidero publishes Talos AMIs for."
  }
}

variable "worker_architecture" {
  type        = string
  default     = "amd64"
  description = "CPU architecture of the worker AMI. Must match the architecture of worker_instance_type, and of whatever Karpenter is allowed to launch."

  validation {
    condition     = contains(["amd64", "arm64"], var.worker_architecture)
    error_message = "worker_architecture must be amd64 or arm64: those are the architectures Sidero publishes Talos AMIs for."
  }
}

variable "control_plane_root_volume_size" {
  type        = number
  default     = 50
  description = "Size of the control plane root volume in GiB."

  validation {
    condition     = var.control_plane_root_volume_size >= 20
    error_message = "control_plane_root_volume_size must be at least 20 GiB: below that the EPHEMERAL partition leaves no room for etcd's data directory and the control plane images."
  }
}

variable "worker_root_volume_size" {
  type        = number
  default     = 50
  description = "Size of the baseline worker root volume in GiB. This is where container images and ephemeral storage live, so it is the one to raise for an image-heavy workload."

  validation {
    condition     = var.worker_root_volume_size >= 20
    error_message = "worker_root_volume_size must be at least 20 GiB: below that the EPHEMERAL partition leaves no room for container images."
  }
}
