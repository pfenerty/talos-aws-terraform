variable "project_name" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "load_balancer_dns" {
  type = string
}

variable "control_plane_nodes" {
  type = list(object({
    private_ip = string
    public_ip  = string
  }))
}

variable "worker_nodes" {
  type = list(object({
    private_ip = string
    public_ip  = string
  }))
}

variable "aws_topology" {
  type = object({
    region           = string
    az               = string
    cp_instance_type = string
    wk_instance_type = string
  })
}

variable "cni" {
  type = string
}

variable "disable_kube_proxy" {
  type = bool
}

variable "cilium" {
  type = bool
}

variable "cilium_version" {
  type = string
}

variable "cilium_proxy_replacement" {
  type = bool
}

variable "cilium_enable_hubble" {
  type = bool
}