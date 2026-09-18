# One IRSA role: a role a single Kubernetes service account may assume, by
# presenting a token the cluster signed.
#
# The trust policy is the whole of the security boundary. `sub` pins it to one
# service account in one namespace, so a token from any other workload in the
# cluster is refused; `aud` pins it to the audience AWS requires, so a token
# minted for something else - the API server itself, say - cannot be replayed
# here. Both conditions are `StringEquals` rather than `StringLike`: a
# wildcard in `sub` is how these roles are usually mis-scoped.
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc.issuer_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

resource "aws_iam_policy" "this" {
  name   = var.name
  policy = var.policy

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
