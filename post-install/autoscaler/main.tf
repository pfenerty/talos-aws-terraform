resource "aws_iam_user" "this" {
  name = "${var.project_name}_autoscaler"
}

resource "aws_iam_policy" "this" {
  name = "${var.project_name}_autoscaler"
  policy = templatefile("${path.module}/iam.json.tmpl", {
    account_id   = var.aws_account_id,
    project_name = var.project_name
  })
}

resource "aws_iam_user_policy_attachment" "this" {
  user       = aws_iam_user.this.name
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

resource "kubernetes_secret" "this" {
  metadata {
    name      = "cluster-autoscaler-config"
    namespace = "flux-system"
  }

  data = {
    access-key-id     = aws_iam_access_key.this.id
    secret-access-key = aws_iam_access_key.this.secret
    cluster-name      = var.project_name
    region            = var.region
  }
}