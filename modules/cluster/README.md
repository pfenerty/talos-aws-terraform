# modules / cluster

The AWS and Talos half: VPC, load balancer, security groups, autoscaling
groups, machine configuration and the Talos bootstrap. It produces a
cluster whose control plane is up and whose `kubeconfig` works, but whose
nodes are still `NotReady` - Talos runs with `cni: none`, so nothing
schedules until a CNI is installed. `modules/bootstrap` does that.

This module configures no providers. It needs `aws`, `talos` and `local`
from the caller, all of which can be configured up front, which is what
makes it safe to use with `count` and `for_each`.

## Generated files

Nothing is written to disk unless `config_output_path` is set. The
kubeconfig, talosconfig and machine configs are available as outputs
either way, and they all carry cluster credentials.

## Machine config size

The control plane machine config is applied as EC2 user data, which AWS
limits to 16 KB. A generated Talos control plane config is already around
11 KB before this module's patches, so there is roughly 5 KB of headroom.
Anything added to `common_machine_config_patch` in `talos/config` spends
it, and running out fails the apply with an AWS error that does not
mention the limit. This is why Cilium is installed with Helm rather than
as a Talos inline manifest: rendered, it is about 68 KB.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |
| local | ~> 2.9 |
| talos | ~> 0.11 |

## Providers

| Name | Version |
|------|---------|
| aws | 6.65.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| compute | ./cloud-infra/compute | n/a |
| networking | ./cloud-infra/networking | n/a |
| talos\_bootstrap | ./talos/bootstrap | n/a |
| talos\_config | ./talos/config | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_instances.control_plane_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances) | data source |
| [aws_instances.worker_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| additional\_tags | Extra tags applied to every resource this module creates, on top of the cluster, ManagedBy and Project tags. | `map(string)` | `{}` | no |
| availability\_zones | Availability Zones to create subnets in. Null means every zone the region currently reports, which is convenient but means the subnet layout changes if AWS adds a zone; pin it for anything long-lived. The availability\_zones output reports what was used. | `list(string)` | `null` | no |
| config\_output\_path | Directory to write the generated kubeconfig, talosconfig and machine config files into. Null, the default, writes nothing: the same files are available as outputs, and a module that writes into the caller's directory collides with itself when instantiated more than once. The files carry cluster credentials and are written mode 0600. | `string` | `null` | no |
| control\_plane\_node\_instance\_type | AWS EC2 instance type for control plane nodes | `string` | `"t3.medium"` | no |
| control\_plane\_nodes | Number of control plane nodes. etcd needs an odd number to hold quorum; 1 is fine for a throwaway cluster but has no redundancy, and an instance refresh will briefly take the API server away. | `number` | `1` | no |
| hardening | Machine config hardening, off by default because it changes what the cluster will admit. Passed through to the Talos config module; see docs/hardening.md for what it covers, what it deliberately leaves alone, and what has to be enforced outside the machine config. kubelet\_serving\_certificates additionally requires a CSR approver deployed by Flux; see the doc before enabling it. | <pre>object({<br/>    enabled                        = optional(bool, false)<br/>    pod_security_enforce           = optional(string, "restricted")<br/>    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])<br/>    kubelet_serving_certificates   = optional(bool, false)<br/>  })</pre> | `{}` | no |
| kubernetes\_api\_allowed\_cidr | CIDR allowed to reach the Kubernetes API on port 6443. Open to the internet by default; narrow it to your own address where you can. | `string` | `"0.0.0.0/0"` | no |
| kubernetes\_version | Kubernetes version | `string` | `"1.37.0"` | no |
| pod\_cidr | Pod subnet CIDR. Set on the Talos machine config and reused as Cilium's strict-mode egress CIDR so the two cannot drift apart. | `string` | `"10.244.0.0/16"` | no |
| project\_name | Project name. Used as the prefix for every AWS resource name, as the Talos cluster name, and verbatim as the load balancer and target group name - which is what the constraints below come from. Required: every name this module creates derives from it, and several of them are account-global. | `string` | n/a | yes |
| region | AWS region the cluster runs in. This selects the Talos AMI and is handed to Karpenter; it does not configure the AWS provider, which is the caller's to set. | `string` | n/a | yes |
| talos\_api\_allowed\_cidr | CIDR allowed to reach the Talos API on port 50000. The default is open to the internet, which is what makes `terraform apply` work from anywhere but is the wrong setting for anything you care about: the Talos API administers the machines themselves. Narrow it to your own address. | `string` | `"0.0.0.0/0"` | no |
| talos\_version | Talos Linux version | `string` | `"v1.14.1"` | no |
| vpc\_cidr | IPv4 CIDR block for the VPC. Subnets are carved out of it with a /8 offset per Availability Zone, so it needs to be large enough for one /24 per zone. | `string` | `"172.31.0.0/16"` | no |
| worker\_node\_instance\_type | AWS EC2 instance type for worker nodes | `string` | `"t3.medium"` | no |
| worker\_nodes\_max | Ceiling on the worker autoscaling group. Only reached by scaling the group by hand; elastic capacity comes from Karpenter instead. Must leave at least one instance of headroom above worker\_nodes\_min, which is what a rolling instance refresh launches its replacement into. | `number` | `5` | no |
| worker\_nodes\_min | Size the worker autoscaling group is created at. Nothing scales this group: it is the static baseline that Karpenter itself and the rest of the cluster add-ons run on, and Karpenter provisions everything above it. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| availability\_zones | Availability Zones the subnets were created in. Pin var.availability\_zones to this list to stop the layout moving. |
| bootstrap\_inputs | Cluster facts consumed by the bootstrap module. Pass straight to its `cluster` variable. |
| client\_configuration | Talos client certificates, for the Talos provider's own data sources and resources. |
| cluster\_endpoint | Kubernetes API endpoint, and the Talos cluster endpoint. |
| control\_plane\_autoscaling\_group\_name | Name of the control plane autoscaling group. |
| control\_plane\_private\_ips | Private addresses of the control plane nodes, which is how Talos identifies them. |
| control\_plane\_public\_ips | Public addresses of the control plane nodes. The Talos API listens here; node addresses themselves are private. |
| kubeconfig | Admin kubeconfig for the cluster. Contains cluster credentials. |
| load\_balancer\_dns | DNS name of the network load balancer in front of the control plane. |
| node\_count | Number of nodes the cluster is created with, before Karpenter provisions anything. Used to size add-ons whose replica counts cannot exceed the number of nodes. |
| oidc\_issuer\_url | URL the API server names as the issuer of its service account tokens, and where the bootstrap module publishes the OIDC discovery documents. Registered with AWS as an IAM identity provider. |
| subnet\_ids | Subnets the cluster runs in, ordered by Availability Zone. |
| talos\_ami\_id | AMI the cluster nodes boot from. |
| talosconfig | Talos client configuration. Contains cluster credentials. |
| vpc\_id | ID of the VPC the cluster runs in. |
| worker\_private\_ips | Private addresses of the baseline worker nodes. |
<!-- END_TF_DOCS -->
