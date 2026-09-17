# cloud-infra / compute

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 6.65 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_attachment.asg_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment) | resource |
| [aws_autoscaling_group.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_group.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_instance_profile.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.control_plane_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.worker_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_ami.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| control\_plane\_instance\_type | EC2 instance type for control plane nodes. | `string` | n/a | yes |
| control\_plane\_machine\_config | Talos control plane machine config, applied as launch template user data. | `string` | n/a | yes |
| control\_plane\_nodes | Size of the control plane autoscaling group. The group's max\_size is one higher, so an instance refresh can launch a replacement before terminating a node. | `number` | n/a | yes |
| control\_plane\_security\_group\_id | Security group granting external access to the Kubernetes and Talos APIs. | `string` | n/a | yes |
| internal\_security\_group\_id | Security group allowing node-to-node traffic and outbound access. | `string` | n/a | yes |
| load\_balancer\_target\_group\_arn | Target group the control plane autoscaling group registers into. | `string` | n/a | yes |
| project\_name | Project name, used to name and tag the compute resources. | `string` | n/a | yes |
| region | AWS region, used to select the Talos AMI published for it. | `string` | n/a | yes |
| subnets | Subnets the autoscaling groups launch instances into. | `list(string)` | n/a | yes |
| tags | Tags applied to every resource, and propagated to the instances the autoscaling groups launch. Carries the kubernetes.io/cluster tag the AWS cloud controller manager looks for. | `map(string)` | `{}` | no |
| talos\_version | Talos Linux version, used to select the matching AMI. | `string` | n/a | yes |
| worker\_instance\_type | EC2 instance type for the baseline worker nodes. | `string` | n/a | yes |
| worker\_machine\_config | Talos worker machine config, applied as launch template user data. | `string` | n/a | yes |
| worker\_nodes\_max | Ceiling on the worker autoscaling group. Must exceed worker\_nodes\_min to leave an instance refresh room to work. | `number` | n/a | yes |
| worker\_nodes\_min | Size the worker autoscaling group is created at and stays at; Karpenter provisions capacity above it. | `number` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| control\_plane\_autoscaling\_group\_name | n/a |
| talos\_ami\_id | n/a |
| worker\_autoscaling\_group\_name | n/a |
| worker\_iam\_role\_arn | n/a |
| worker\_instance\_profile\_name | Karpenter launches nodes into the worker role's instance profile rather than creating one of its own, which keeps the instance-profile write permissions out of the controller's policy. |
<!-- END_TF_DOCS -->
