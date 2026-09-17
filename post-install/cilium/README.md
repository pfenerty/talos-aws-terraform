# post-install / cilium

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| helm | 3.3.0 |
| kubernetes | 3.2.1 |
| tls | 4.4.1 |

## Providers

| Name | Version |
|------|---------|
| helm | 3.3.0 |
| kubernetes | 3.2.1 |
| tls | 4.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/3.3.0/docs/resources/release) | resource |
| [kubernetes_secret_v1.hubble_trust_anchor](https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.1/docs/resources/secret_v1) | resource |
| [tls_private_key.hubble](https://registry.terraform.io/providers/hashicorp/tls/4.4.1/docs/resources/private_key) | resource |
| [tls_self_signed_cert.hubble](https://registry.terraform.io/providers/hashicorp/tls/4.4.1/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cilium\_version | Cilium chart version to install. | `string` | n/a | yes |
| pod\_cidr | Pod subnet CIDR, used as the Cilium strict-mode egress CIDR | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
