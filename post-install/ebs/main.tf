resource "aws_iam_user" "ebs" {
  name = "${var.project_name}_ebs_svc"
}

resource "aws_iam_user_policy" "ebs" {
  name   = "${var.project_name}_ebs"
  user   = aws_iam_user.ebs.name
  policy = file("${path.module}/ebs-iam.json")
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