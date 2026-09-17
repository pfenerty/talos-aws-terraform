variable "project_name" {
  type        = string
  description = "Project name, used as the Talos cluster name."
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version the machine secrets and configs are generated for."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version written into the machine configs."
}

variable "load_balancer_dns" {
  type        = string
  description = "DNS name of the control plane load balancer, used as the cluster endpoint."
}
variable "pod_cidr" {
  type        = string
  description = "Pod subnet CIDR"
}

variable "config_output_path" {
  type        = string
  default     = null
  description = "Directory to write talosconfig and the generated machine configs into. Null writes nothing."
}

variable "hardening" {
  type = object({
    enabled                        = optional(bool, false)
    pod_security_enforce           = optional(string, "restricted")
    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])
  })
  default     = {}
  description = "Machine config hardening, off by default because it changes what the cluster will admit. See docs/hardening.md for what it does and does not cover, and for the settings Talos already applies without it. enabled turns on the hardened API server audit policy and the Pod Security Admission configuration described below. It has no worker half: everything a benchmark asks for on the node is already how Talos generates and runs the kubelet. pod_security_enforce is the Pod Security Standard enforced cluster-wide, and pod_security_exempt_namespaces the namespaces exempted from it - kube-system has to stay exempt for Cilium, which needs a privileged pod to run at all."

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.hardening.pod_security_enforce)
    error_message = "hardening.pod_security_enforce must be one of privileged, baseline or restricted: they are the three Pod Security Standards."
  }

  validation {
    condition     = !var.hardening.enabled || contains(var.hardening.pod_security_exempt_namespaces, "kube-system")
    error_message = "hardening.pod_security_exempt_namespaces must include kube-system. Cilium runs a privileged pod there, and the cluster cannot reach a healthy state without a CNI."
  }
}
