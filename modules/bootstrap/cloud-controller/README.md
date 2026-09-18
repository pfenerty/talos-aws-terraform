# modules / bootstrap / cloud-controller

The AWS cloud controller manager's identity and its cloud configuration.

Both halves exist because the controller no longer reads the instance metadata
service. It used to get two things from it, and the nodes' launch templates
now set an IMDS hop limit of 1, which a pod cannot cross:

* **Credentials**, from the node's instance profile. Now a role it assumes
  with its own service account token. The role's policy is the one that used
  to be attached to the control plane instance profile, unchanged - the
  control plane role is empty as a result, because this was its only consumer.
* **Its region, VPC and instance identity.** Now a cloud config file.
  Upstream calls this path "master is running on a different AWS account,
  different cloud provider or on-premise": given `VPC`, `SubnetID` and
  `KubernetesClusterID`, the controller builds a synthetic self-instance and
  never calls metadata. `KubernetesClusterID` is not optional there - without
  it the controller tries to describe the synthetic instance and fails at
  startup. `SubnetID` is used only to build that instance; load balancers
  still choose their subnets by tag.

Both files are keys of one ConfigMap, because both carry values specific to
one cluster and the Flux bootstrap repository holds none. They arrive as a
file rather than as environment variables - which is how the EBS CSI driver
and Karpenter take the same thing - because this chart has no `envFrom` and
its `env` is a plain Helm value.

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
| oidc | The cluster's IAM identity provider. Pass the oidc module's outputs. | <pre>object({<br/>    provider_arn = string<br/>    issuer_host  = string<br/>  })</pre> | n/a | yes |
| project\_name | Project name, used as the role name prefix and as the cloud controller's KubernetesClusterID - which must match the kubernetes.io/cluster tag on the cluster's resources. | `string` | n/a | yes |
| region | AWS region the cluster runs in. Set explicitly because the controller can no longer read it from instance metadata. | `string` | n/a | yes |
| subnet\_id | Any subnet in that VPC. Used only to build the controller's synthetic self-instance; load balancer placement is decided by subnet tags. | `string` | n/a | yes |
| tags | Tags applied to every resource this module creates. | `map(string)` | `{}` | no |
| token\_path | Path the projected service account token is mounted at in the controller's pod. Must match the volume mount in the Flux bootstrap repository. | `string` | n/a | yes |
| vpc\_id | VPC the cluster runs in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| role\_arn | ARN of the role the cloud controller manager assumes. |
<!-- END_TF_DOCS -->
