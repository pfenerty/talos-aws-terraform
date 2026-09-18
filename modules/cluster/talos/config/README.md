# talos / config

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| local | ~> 2.9 |
| talos | ~> 0.11 |

## Providers

| Name | Version |
|------|---------|
| local | ~> 2.9 |
| talos | ~> 0.11 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.machineconfig_cp](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.machineconfig_karpenter_worker](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.machineconfig_worker](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.talosconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [talos_machine_secrets.machine_secrets](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.talosconfig](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.machineconfig_cp](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.machineconfig_karpenter_worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.machineconfig_worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| config\_output\_path | Directory to write talosconfig and the generated machine configs into. Null writes nothing. | `string` | `null` | no |
| hardening | Machine config hardening, off by default because it changes what the cluster will admit. See docs/hardening.md for what it does and does not cover, and for the settings Talos already applies without it. enabled turns on the hardened API server audit policy and the Pod Security Admission configuration described below. kubelet\_serving\_certificates makes the kubelet bootstrap a CA-signed serving certificate instead of self-signing one, and the API server verify it. It requires a CSR approver running in the cluster - a Flux dependency, not something this module can install - because kube-controller-manager will not approve kubelet-serving CSRs itself. Turning it on without one leaves nodes registering and running pods but breaks kubectl logs, exec, port-forward and metrics-server until the approver lands. Apart from that, hardening has no worker half: everything else a benchmark asks for on the node is already how Talos generates and runs the kubelet. pod\_security\_enforce is the Pod Security Standard enforced cluster-wide, and pod\_security\_exempt\_namespaces the namespaces exempted from it - kube-system has to stay exempt for Cilium, which needs a privileged pod to run at all. | <pre>object({<br/>    enabled                        = optional(bool, false)<br/>    pod_security_enforce           = optional(string, "restricted")<br/>    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])<br/>    kubelet_serving_certificates   = optional(bool, false)<br/>  })</pre> | `{}` | no |
| kubernetes\_talos\_api\_access | Lets service accounts in the named namespaces obtain Talos API credentials with the named roles. Off by default. This is how an in-cluster upgrade controller reaches the Talos API, and it is a real widening of the cluster's trust boundary: os:admin can read and replace the machine config. The namespace is the only granularity Talos offers, so it has to hold nothing but the controller, and it has to match the controller's release namespace exactly. See docs/hardening.md. | <pre>object({<br/>    enabled    = optional(bool, false)<br/>    roles      = optional(list(string), ["os:admin"])<br/>    namespaces = optional(list(string), ["tuppr-system"])<br/>  })</pre> | `{}` | no |
| kubernetes\_version | Kubernetes version written into the machine configs. | `string` | n/a | yes |
| load\_balancer\_dns | DNS name of the control plane load balancer, used as the cluster endpoint. | `string` | n/a | yes |
| pod\_cidr | Pod subnet CIDR | `string` | n/a | yes |
| project\_name | Project name, used as the Talos cluster name. | `string` | n/a | yes |
| service\_account\_issuer | URL the API server names as the issuer of service account tokens, and where its OpenID Connect discovery documents are published. Set to the OIDC bucket's HTTPS URL so that AWS can verify the tokens IRSA trades for role credentials. Changing it on a running cluster invalidates every service account token until the kubelets refresh them. | `string` | n/a | yes |
| talos\_version | Talos Linux version the machine secrets and configs are generated for. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| client\_configuration | n/a |
| control\_plane\_machine\_config | n/a |
| karpenter\_worker\_machine\_config | Worker machine config for nodes launched by Karpenter. Identical to worker\_machine\_config apart from the karpenter.sh/unregistered taint, and used as the EC2NodeClass user data. |
| talosconfig | n/a |
| worker\_machine\_config | n/a |
<!-- END_TF_DOCS -->
