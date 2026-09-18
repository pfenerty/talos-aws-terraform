# modules / bootstrap / oidc

The cluster's OpenID Connect discovery documents, published where AWS can read
them, and registered with IAM as an identity provider. This is what makes IRSA
work without EKS.

AWS will trade a projected service account token for role credentials only if
it can verify the token's signature, and to do that it needs the issuer's
discovery document and public keys at a public HTTPS URL. On EKS the control
plane serves them. Here the API server cannot: anonymous authentication is
off, and turning it on to expose two documents would be a far worse trade than
an S3 bucket.

Neither document is secret. Between them they are a public key and a
description of where to find it; every token they let AWS verify was signed by
a private key that never leaves the control plane.

## Why they are copied rather than written

Both are read from the API server over mutual TLS and uploaded as they are.
The alternative is to build them from the service account signing key, which
Terraform does hold - but the JWKS carries a key ID that Kubernetes derives by
hashing the DER encoding of the public key, and a key ID that does not match
the one in the token header is a key AWS will not find. Copying the documents
removes the possibility of disagreeing with the API server about any of it.

The bucket name is decided by the cluster module rather than here, because the
issuer URL built from it is an API server argument, and that argument is baked
into the machine config the cluster module renders.

## Order

The IAM identity provider is created after both objects exist. AWS fetches the
discovery document when the provider is created, to work out the endpoint's
certificate thumbprint, and would fail against an empty bucket. The thumbprint
is left to AWS to retrieve rather than pinned here, which is also what keeps
this working when the endpoint's CA rotates.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |
| http | ~> 3.5 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 6.65 |
| http | ~> 3.5 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_object.jwks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.openid_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [http_http.jwks](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |
| [http_http.openid_configuration](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket\_name | Name of the bucket the OIDC discovery documents are published to. Decided by the cluster module, because the issuer URL built from it is baked into the API server's machine config. | `string` | n/a | yes |
| cluster\_endpoint | Kubernetes API endpoint, read to fetch the cluster's own discovery documents. | `string` | n/a | yes |
| issuer\_url | URL the API server names as the issuer of its service account tokens. Must be the HTTPS URL of the bucket above, and must match the iss claim in the tokens byte for byte. | `string` | n/a | yes |
| kubernetes\_client\_configuration | Admin client certificate for the Kubernetes API. The discovery endpoints are not anonymous on this cluster, so reading them needs one. | <pre>object({<br/>    ca_certificate     = string<br/>    client_certificate = string<br/>    client_key         = string<br/>  })</pre> | n/a | yes |
| tags | Tags applied to every resource this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket | Name of the bucket the discovery documents are published to. |
| issuer\_host | Issuer URL without its scheme, which is the form IAM condition keys take: `<issuer_host>:sub` and `<issuer_host>:aud`. |
| provider\_arn | ARN of the IAM identity provider. Named as the federated principal in every IRSA role's trust policy. |
<!-- END_TF_DOCS -->
