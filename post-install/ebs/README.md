# post-install / ebs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | 6.65.0 |
| kubernetes | 3.2.1 |

## Providers

| Name | Version |
|------|---------|
| aws | 6.65.0 |
| kubernetes | 3.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_access_key.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.65.0/docs/resources/iam_access_key) | resource |
| [aws_iam_policy.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.65.0/docs/resources/iam_policy) | resource |
| [aws_iam_user.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.65.0/docs/resources/iam_user) | resource |
| [aws_iam_user_policy_attachment.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.65.0/docs/resources/iam_user_policy_attachment) | resource |
| [kubernetes_secret_v1.ebs](https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.1/docs/resources/secret_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_account\_id | Account ID, scoping the EBS CSI driver's policy to this account's volumes. | `string` | n/a | yes |
| project\_name | Project name, used to name the EBS CSI driver's IAM user and policy. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
