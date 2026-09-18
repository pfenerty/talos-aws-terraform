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
    kubelet_serving_certificates   = optional(bool, false)
  })
  default     = {}
  description = "Machine config hardening, off by default because it changes what the cluster will admit. See docs/hardening.md for what it does and does not cover, and for the settings Talos already applies without it. enabled turns on the hardened API server audit policy and the Pod Security Admission configuration described below. kubelet_serving_certificates makes the kubelet bootstrap a CA-signed serving certificate instead of self-signing one, and the API server verify it. It requires a CSR approver running in the cluster - a Flux dependency, not something this module can install - because kube-controller-manager will not approve kubelet-serving CSRs itself. Turning it on without one leaves nodes registering and running pods but breaks kubectl logs, exec, port-forward and metrics-server until the approver lands. Apart from that, hardening has no worker half: everything else a benchmark asks for on the node is already how Talos generates and runs the kubelet. pod_security_enforce is the Pod Security Standard enforced cluster-wide, and pod_security_exempt_namespaces the namespaces exempted from it - kube-system has to stay exempt for Cilium, which needs a privileged pod to run at all."

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.hardening.pod_security_enforce)
    error_message = "hardening.pod_security_enforce must be one of privileged, baseline or restricted: they are the three Pod Security Standards."
  }

  validation {
    condition     = !var.hardening.enabled || contains(var.hardening.pod_security_exempt_namespaces, "kube-system")
    error_message = "hardening.pod_security_exempt_namespaces must include kube-system. Cilium runs a privileged pod there, and the cluster cannot reach a healthy state without a CNI."
  }

  validation {
    condition     = !var.hardening.kubelet_serving_certificates || var.hardening.enabled
    error_message = "hardening.kubelet_serving_certificates requires hardening.enabled: the sub-settings only apply when hardening is on, and silently ignoring it would be worse than refusing it."
  }
}

variable "service_account_issuer" {
  type        = string
  description = "URL the API server names as the issuer of service account tokens, and where its OpenID Connect discovery documents are published. Set to the OIDC bucket's HTTPS URL so that AWS can verify the tokens IRSA trades for role credentials. Changing it on a running cluster invalidates every service account token until the kubelets refresh them."

  validation {
    condition     = startswith(var.service_account_issuer, "https://") && !endswith(var.service_account_issuer, "/")
    error_message = "service_account_issuer must be an https URL with no trailing slash: it has to match the iss claim in the tokens byte for byte, and the discovery document is served from it by appending a path."
  }
}

variable "kubernetes_talos_api_access" {
  type = object({
    enabled    = optional(bool, false)
    roles      = optional(list(string), ["os:admin"])
    namespaces = optional(list(string), ["tuppr-system"])
  })
  default     = {}
  description = "Lets service accounts in the named namespaces obtain Talos API credentials with the named roles. Off by default. This is how an in-cluster upgrade controller reaches the Talos API, and it is a real widening of the cluster's trust boundary: os:admin can read and replace the machine config. The namespace is the only granularity Talos offers, so it has to hold nothing but the controller, and it has to match the controller's release namespace exactly. See docs/hardening.md."

  validation {
    condition     = !var.kubernetes_talos_api_access.enabled || (length(var.kubernetes_talos_api_access.roles) > 0 && length(var.kubernetes_talos_api_access.namespaces) > 0)
    error_message = "kubernetes_talos_api_access.roles and .namespaces must both be non-empty when enabled, or the feature is turned on while granting nothing."
  }
}
