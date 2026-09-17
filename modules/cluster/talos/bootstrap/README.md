# talos / bootstrap

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
| [local_sensitive_file.kubeconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [talos_cluster_kubeconfig.kubeconfig](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.talos_bootstrap](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| client\_configuration | Talos client certificates produced by the config module. | <pre>object({<br/>    ca_certificate     = string<br/>    client_certificate = string<br/>    client_key         = string<br/>  })</pre> | n/a | yes |
| config\_output\_path | Directory to write the generated kubeconfig into. Null writes nothing; the kubeconfig is an output regardless. | `string` | `null` | no |
| private\_ip | Private IP of the same control plane node, used as the Talos node address. | `string` | n/a | yes |
| public\_ip | Public IP of a control plane node, used as the Talos API endpoint. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| kubeconfig | n/a |
<!-- END_TF_DOCS -->
