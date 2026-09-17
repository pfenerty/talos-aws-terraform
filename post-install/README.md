# post-install

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | 6.65.0 |
| flux | 1.9.5 |
| helm | 3.3.0 |
| kubernetes | 3.2.1 |
| random | 3.9.1 |
| talos | 0.11.0 |
| tls | 4.4.1 |

## Providers

| Name | Version |
|------|---------|
| aws | 6.65.0 |
| flux | 1.9.5 |
| kubernetes | 3.2.1 |
| random | 3.9.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| cilium | ./cilium | n/a |
| ebs | ./ebs | n/a |
| karpenter | ./karpenter | n/a |

## Resources

| Name | Type |
|------|------|
| [flux_bootstrap_git.this](https://registry.terraform.io/providers/fluxcd/flux/1.9.5/docs/resources/bootstrap_git) | resource |
| [kubernetes_secret_v1.aws_lb_config](https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.1/docs/resources/secret_v1) | resource |
| [random_uuid.cluster_flux_id](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/uuid) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.65.0/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cilium\_version | Cilium chart version to install. | `string` | n/a | yes |
| cluster\_endpoint | Kubernetes API endpoint, handed to Karpenter | `string` | n/a | yes |
| enables | Mirror of the root post\_install variable: which post-install steps to run, and the Flux git credentials. | <pre>object({<br/>    flux = object({<br/>      enabled    = bool<br/>      git_url    = string<br/>      git_branch = string<br/>      ssh_key    = string<br/>    })<br/>    extras = object({<br/>      ebs       = bool<br/>      karpenter = bool<br/>    })<br/>  })</pre> | <pre>{<br/>  "extras": {<br/>    "ebs": false,<br/>    "karpenter": false<br/>  },<br/>  "flux": {<br/>    "enabled": false,<br/>    "git_branch": "",<br/>    "git_url": "",<br/>    "ssh_key": ""<br/>  }<br/>}</pre> | no |
| k8s\_service\_host | Control plane load balancer DNS, published to the cluster in a secret. | `string` | n/a | yes |
| karpenter\_worker\_machine\_config | Talos worker machine config used as the EC2NodeClass user data | `string` | n/a | yes |
| pod\_cidr | Pod subnet CIDR | `string` | n/a | yes |
| project\_name | Project name, used to name the IAM resources and as the Karpenter cluster name. | `string` | n/a | yes |
| region | AWS region, passed to Karpenter so it launches nodes in the right place. | `string` | n/a | yes |
| worker\_ami\_id | Talos AMI Karpenter launches nodes from | `string` | n/a | yes |
| worker\_iam\_role\_arn | Role behind worker\_instance\_profile\_name, scoping Karpenter's iam:PassRole grant | `string` | n/a | yes |
| worker\_instance\_profile\_name | Instance profile Karpenter launches nodes into | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
