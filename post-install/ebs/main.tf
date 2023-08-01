resource "aws_iam_user" "ebs" {
  name = "${var.project_name}_ebs_svc"
}

resource "aws_iam_policy" "ebs" {
  name   = "${var.project_name}_ebs"
  policy = templatefile("${path.module}/ebs-iam.json.tmpl", {
    account_id = var.aws_account_id,
    project_name = var.project_name
  })
}

resource "aws_iam_user_policy_attachment" "ebs" {
  user = aws_iam_user.ebs.name
  policy_arn = aws_iam_policy.ebs.arn
}

resource "aws_iam_access_key" "ebs" {
  user = aws_iam_user.ebs.name
}

resource "kubernetes_secret" "ebs" {
  metadata {
    name      = "aws-secret"
    namespace = "kube-system"
  }

  data = {
    key_id     = aws_iam_access_key.ebs.id
    access_key = aws_iam_access_key.ebs.secret
  }
}