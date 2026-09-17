# talos / bootstrap

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| local | 2.9.1 |
| talos | 0.11.0 |

## Providers

| Name | Version |
|------|---------|
| local | 2.9.1 |
| talos | 0.11.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.kubeconfig](https://registry.terraform.io/providers/hashicorp/local/2.9.1/docs/resources/sensitive_file) | resource |
| [talos_cluster_kubeconfig.kubeconfig](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.talos_bootstrap](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_bootstrap) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| client\_configuration | Talos client certificates produced by the config module. | <pre>object({<br/>    ca_certificate     = string<br/>    client_certificate = string<br/>    client_key         = string<br/>  })</pre> | n/a | yes |
| private\_ip | Private IP of the same control plane node, used as the Talos node address. | `string` | n/a | yes |
| public\_ip | Public IP of a control plane node, used as the Talos API endpoint. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| kubeconfig | n/a |
<!-- END_TF_DOCS -->
