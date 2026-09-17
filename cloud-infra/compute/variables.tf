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
