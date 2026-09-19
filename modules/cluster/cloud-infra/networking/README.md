# cloud-infra / networking

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
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route.internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_security_group_egress_rule.internal_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.internal_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.kubernetes_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.talos_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.talos_internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| availability\_zones | Availability Zones to create subnets in. Null means every zone the region currently reports, which is convenient but means the layout changes if AWS adds a zone; pin it for anything long-lived. It is also billed: the load balancer puts a node, and a chargeable public IPv4 address, in every subnet it spans. | `list(string)` | `null` | no |
| enable\_cross\_zone\_load\_balancing | Let each load balancer node forward to control plane targets in any zone. On by default, because with fewer control plane nodes than subnets some zones hold no target at all. Off avoids inter-AZ transfer charges, and is only safe with a control plane node in every subnet. | `bool` | `true` | no |
| kubernetes\_api\_allowed\_cidr | The CIDR from which to allow to access the Kubernetes API | `string` | n/a | yes |
| project\_name | Project name, used to name and tag the network resources and as the Karpenter discovery tag value. | `string` | n/a | yes |
| tags | Tags applied to every resource. Carries the kubernetes.io/cluster tag the AWS cloud controller manager looks for, so it is not optional in practice - the parent module always sets it. | `map(string)` | `{}` | no |
| talos\_api\_allowed\_cidr | The CIDR from which to allow to access the Talos API | `string` | n/a | yes |
| vpc\_cidr | The IPv4 CIDR block for the VPC. | `string` | `"172.31.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| availability\_zones | n/a |
| control\_plane\_security\_group\_id | n/a |
| internal\_security\_group\_id | n/a |
| load\_balancer\_arn | n/a |
| load\_balancer\_dns | n/a |
| load\_balancer\_target\_group\_arn | n/a |
| public\_subnets | n/a |
| vpc\_id | n/a |
<!-- END_TF_DOCS -->
