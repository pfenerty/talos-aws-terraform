# post-install / karpenter

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
| aws | ~> 6.65 |
| kubernetes | ~> 3.2 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_iam_access_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key) | resource |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_sqs_queue.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [kubernetes_secret_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_account\_id | Account ID, scoping the controller policy's resource ARNs. | `string` | n/a | yes |
| cluster\_endpoint | Kubernetes API endpoint. Karpenter discovers this from the EKS API when it is not set, which is not an option for a self-managed cluster. | `string` | n/a | yes |
| node\_ami\_id | Talos AMI the EC2NodeClass selects. Pinned rather than discovered so Karpenter nodes cannot drift off the Talos version the rest of the cluster runs. | `string` | n/a | yes |
| node\_iam\_role\_arn | Role behind node\_instance\_profile\_name, scoping the controller's iam:PassRole grant. | `string` | n/a | yes |
| node\_instance\_profile\_name | Instance profile Karpenter launches nodes into. Reuses the worker profile so Karpenter never needs instance-profile write permissions. | `string` | n/a | yes |
| node\_user\_data | Talos worker machine config used as the EC2NodeClass user data. | `string` | n/a | yes |
| project\_name | Project name, used to name Karpenter's AWS resources and as the cluster name it reports. | `string` | n/a | yes |
| region | AWS region Karpenter launches nodes in. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
