# post-install / cilium

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| helm | ~> 3.3 |
| kubernetes | ~> 3.2 |
| tls | ~> 4.4 |

## Providers

| Name | Version |
|------|---------|
| helm | ~> 3.3 |
| kubernetes | ~> 3.2 |
| tls | ~> 4.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_secret_v1.hubble_trust_anchor](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [tls_private_key.hubble](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.hubble](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cilium\_version | Cilium chart version for the bootstrap install. Only ever used to create the release; Flux owns it afterwards. | `string` | n/a | yes |
| hubble\_ca\_validity\_hours | Lifetime of the self-signed Hubble trust anchor, in hours. | `number` | n/a | yes |
| operator\_replicas | Replica count for cilium-operator. The chart default of 2 carries a required anti-affinity on hostname, so this must not exceed the number of nodes the cluster is created with. | `number` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
