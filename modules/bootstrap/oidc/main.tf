# The cluster's OpenID Connect discovery documents, published where AWS can
# read them, and registered with IAM as an identity provider.
#
# This is what makes IRSA work off EKS. AWS will trade a projected service
# account token for role credentials only if it can verify the token's
# signature, and to do that it needs the issuer's discovery document and
# public keys at a public HTTPS URL. On EKS the control plane serves them.
# Here the API server cannot: anonymous authentication is off, and turning it
# on to expose two documents would be a far worse trade than an S3 bucket.
#
# Neither document is secret. Between them they are a public key and a
# description of where to find it; every token they let AWS verify was signed
# by a private key that never leaves the control plane.
#
# Both are copied from the API server rather than written here, so they cannot
# disagree with it. The JWKS in particular carries a key ID derived from the
# public key's DER encoding, which is not something to reproduce by hand.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  # The only objects in here are the two documents below, both of which
  # Terraform re-creates from the cluster. Without this a destroy fails on a
  # non-empty bucket, because versioning leaves delete markers behind.
  force_destroy = true

  tags = var.tags
}

# ACLs off entirely. Public read is granted by the bucket policy below, to two
# object keys by name, which is a thing that can be read and reviewed - an ACL
# is not.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls   = true
  ignore_public_acls  = true
  block_public_policy = false

  # Both of these have to be false for an anonymous GET to succeed, which is
  # the entire purpose of this bucket: an OIDC issuer AWS cannot reach is an
  # OIDC issuer that does not work.
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "PublicReadDiscoveryDocuments"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [for key in local.object_keys : "${aws_s3_bucket.this.arn}/${key}"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  depends_on = [aws_s3_bucket_public_access_block.this]

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json
}

locals {
  # The paths the API server's own discovery document names. `jwks_uri` is
  # derived by Kubernetes as <issuer>/openid/v1/jwks unless it is set
  # explicitly, and it is not, so the object key has to mirror that path.
  object_keys = [".well-known/openid-configuration", "openid/v1/jwks"]
}

# Read over mutual TLS with the admin client certificate. The discovery
# endpoints are not anonymous on this cluster - anonymous-auth is off - so
# there is no way to fetch them without one.
data "http" "openid_configuration" {
  url             = "${var.cluster_endpoint}/.well-known/openid-configuration"
  ca_cert_pem     = var.kubernetes_client_configuration.ca_certificate
  client_cert_pem = var.kubernetes_client_configuration.client_certificate
  client_key_pem  = var.kubernetes_client_configuration.client_key

  retry {
    attempts     = 5
    min_delay_ms = 1000
    max_delay_ms = 5000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The API server returned ${self.status_code} for its OpenID Connect discovery document. Without it AWS cannot verify service account tokens and nothing using IRSA will get credentials."
    }
  }
}

data "http" "jwks" {
  url             = "${var.cluster_endpoint}/openid/v1/jwks"
  ca_cert_pem     = var.kubernetes_client_configuration.ca_certificate
  client_cert_pem = var.kubernetes_client_configuration.client_certificate
  client_key_pem  = var.kubernetes_client_configuration.client_key

  retry {
    attempts     = 5
    min_delay_ms = 1000
    max_delay_ms = 5000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The API server returned ${self.status_code} for its JWKS. Without it AWS cannot verify service account tokens and nothing using IRSA will get credentials."
    }
  }
}

resource "aws_s3_object" "openid_configuration" {
  bucket        = aws_s3_bucket.this.id
  key           = local.object_keys[0]
  content       = data.http.openid_configuration.response_body
  content_type  = "application/json"
  cache_control = "public, max-age=300"

  tags = var.tags
}

resource "aws_s3_object" "jwks" {
  bucket        = aws_s3_bucket.this.id
  key           = local.object_keys[1]
  content       = data.http.jwks.response_body
  content_type  = "application/json"
  cache_control = "public, max-age=300"

  tags = var.tags
}

# Created after the documents, not before: AWS fetches the discovery document
# to work out the endpoint's certificate thumbprint, and would fail against an
# empty bucket. The thumbprint is left for AWS to retrieve rather than pinned
# here, which is also what keeps this working when the endpoint's CA rotates.
resource "aws_iam_openid_connect_provider" "this" {
  depends_on = [
    aws_s3_object.openid_configuration,
    aws_s3_object.jwks,
    aws_s3_bucket_policy.this,
  ]

  url            = var.issuer_url
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}
