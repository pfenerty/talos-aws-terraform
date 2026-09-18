# modules / bootstrap / irsa-role

One role that one Kubernetes service account may assume, by presenting a token
the cluster signed.

The trust policy is the whole of the security boundary, and it is the reason
this is a module rather than three copies of the same `aws_iam_role`:

* `sub` is pinned to `system:serviceaccount:<namespace>:<name>`, so a token
  from any other workload in the cluster is refused.
* `aud` is pinned to `sts.amazonaws.com`, so a token minted for something else
  - the API server itself, say - cannot be replayed against IAM.

Both are `StringEquals`. A wildcard in `sub` is the usual way these roles end
up granting the whole cluster what one workload needed, and there is no reason
to reach for one here.

`service_account` has to match what the workload's chart actually creates.
Nothing validates that: a mismatch applies cleanly and then fails at
`AssumeRoleWithWebIdentity`, in the workload's logs.

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
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the role and of the policy attached to it. Prefixed with the project name by the caller, as every other AWS resource here is. | `string` | n/a | yes |
| namespace | Namespace of that service account. | `string` | `"kube-system"` | no |
| oidc | The cluster's IAM identity provider. Pass the oidc module's outputs. | <pre>object({<br/>    provider_arn = string<br/>    issuer_host  = string<br/>  })</pre> | n/a | yes |
| policy | The permissions policy, as JSON. What the role may do once assumed. | `string` | n/a | yes |
| service\_account | Name of the Kubernetes service account allowed to assume this role. Must match what the workload's chart actually creates: the trust policy compares it exactly, and a mismatch fails at AssumeRoleWithWebIdentity rather than at apply. | `string` | n/a | yes |
| tags | Tags applied to the role and policy. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| role\_arn | ARN of the role. The workload names it in AWS\_ROLE\_ARN, or in its shared AWS config file. |
| role\_name | Name of the role. |
<!-- END_TF_DOCS -->
