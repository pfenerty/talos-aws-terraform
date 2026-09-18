# post-install / ebs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |
| kubernetes | ~> 3.2 |

## Providers

| Name | Version |
|------|---------|
| kubernetes | ~> 3.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| role | ../irsa-role | n/a |

## Resources

| Name | Type |
|------|------|
| [kubernetes_config_map_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_account\_id | Account ID, scoping the EBS CSI driver's policy to this account's volumes. | `string` | n/a | yes |
| oidc | The cluster's IAM identity provider. Pass the oidc module's outputs. | <pre>object({<br/>    provider_arn = string<br/>    issuer_host  = string<br/>  })</pre> | n/a | yes |
| project\_name | Project name, used to name the EBS CSI driver's IAM role and policy. | `string` | n/a | yes |
| region | AWS region the cluster runs in. Set explicitly because the driver can no longer read it from instance metadata. | `string` | n/a | yes |
| tags | Tags applied to every resource this module creates. | `map(string)` | `{}` | no |
| token\_path | Path the projected service account token is mounted at in the controller's pod. Must match the volume mount in the Flux bootstrap repository. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| role\_arn | ARN of the role the EBS CSI controller assumes. |
<!-- END_TF_DOCS -->
