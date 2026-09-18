output "provider_arn" {
  value       = aws_iam_openid_connect_provider.this.arn
  description = "ARN of the IAM identity provider. Named as the federated principal in every IRSA role's trust policy."
}

output "issuer_host" {
  value       = replace(var.issuer_url, "https://", "")
  description = "Issuer URL without its scheme, which is the form IAM condition keys take: `<issuer_host>:sub` and `<issuer_host>:aud`."
}

output "bucket" {
  value       = aws_s3_bucket.this.id
  description = "Name of the bucket the discovery documents are published to."
}
