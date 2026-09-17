# talos / config

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
| [local_sensitive_file.machineconfig_cp](https://registry.terraform.io/providers/hashicorp/local/2.9.1/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.machineconfig_karpenter_worker](https://registry.terraform.io/providers/hashicorp/local/2.9.1/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.machineconfig_worker](https://registry.terraform.io/providers/hashicorp/local/2.9.1/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.talosconfig](https://registry.terraform.io/providers/hashicorp/local/2.9.1/docs/resources/sensitive_file) | resource |
| [talos_machine_secrets.machine_secrets](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.talosconfig](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.machineconfig_cp](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.machineconfig_karpenter_worker](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.machineconfig_worker](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| kubernetes\_version | Kubernetes version written into the machine configs. | `string` | n/a | yes |
| load\_balancer\_dns | DNS name of the control plane load balancer, used as the cluster endpoint. | `string` | n/a | yes |
| pod\_cidr | Pod subnet CIDR | `string` | n/a | yes |
| project\_name | Project name, used as the Talos cluster name. | `string` | n/a | yes |
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
