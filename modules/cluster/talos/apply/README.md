# talos / apply

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| talos | ~> 0.11 |

## Providers

| Name | Version |
|------|---------|
| talos | ~> 0.11 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [talos_machine_configuration_apply.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| apply\_mode | How Talos applies the configuration. `staged_if_needing_reboot` dry-runs the change and stages it for the next boot if it would need a reboot, applying it immediately otherwise. `auto` reboots where a reboot is required, which Terraform has no way to serialise across the group. | `string` | n/a | yes |
| client\_configuration | Talos client certificates produced by the config module. | <pre>object({<br/>    ca_certificate     = string<br/>    client_certificate = string<br/>    client_key         = string<br/>  })</pre> | n/a | yes |
| endpoints | Talos API addresses to reach the nodes through, indexed alongside `nodes` and wrapped if shorter: a single-element list sends every node's apply through one endpoint, which is how workers are reached. | `list(string)` | n/a | yes |
| machine\_configuration | Rendered Talos machine config for this group of nodes. The same string the launch template carries as user data, so the two channels cannot deliver different configurations. | `string` | n/a | yes |
| node\_count | Number of nodes in the group, taken from its configured size rather than from the instances found. Terraform resolves a resource's count at plan time, and instance addresses are only known once the autoscaling groups have applied. | `number` | n/a | yes |
| nodes | Private addresses of the nodes to apply to, which is how Talos identifies a node. Must be ordered stably - by instance ID - so that an index names the same machine between plans. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| applied\_nodes | Nodes the machine config was applied to, in the order it was applied. |
| resolved\_apply\_modes | The apply mode Talos actually used per node. `staged` means the configuration is on the node but does not take effect until it reboots. |
<!-- END_TF_DOCS -->
