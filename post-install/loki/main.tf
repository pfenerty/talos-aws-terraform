module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${var.project_name}-logging"
}

resource "aws_iam_user" "this" {
  name = "${var.project_name}_logging_s3_storage_svc"
}

resource "aws_iam_policy" "s3" {
  name   = "${var.project_name}_logging_s3_storage"
  policy = templatefile("${path.module}/s3-iam.json.tmpl", {
    project_name = var.project_name
  })
}

resource "aws_iam_policy" "dynamo_db" {
  name   = "${var.project_name}_logging_dynamo_db_storage"
  policy = templatefile("${path.module}/dynamodb-iam.json.tmpl", {
    project_name = var.project_name
  })
}

resource "aws_iam_user_policy_attachment" "s3" {
  user = aws_iam_user.this.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_user_policy_attachment" "dynamo_db" {
  user = aws_iam_user.this.name
  policy_arn = aws_iam_policy.dynamo_db.arn
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

resource "kubernetes_secret" "this" {
  metadata {
    name      = "loki-storage-config"
    namespace = "flux-system"
  }

  data = {
    bucket_name = "${var.project_name}-logging"
    region      = module.s3_bucket.s3_bucket_region
    key_id     = aws_iam_access_key.this.id
    access_key = replace(aws_iam_access_key.this.secret, "/", "\\/")
    dynamodb_url = "dynamodb://${var.region}"
    s3_url = "s3://${var.region}/${var.project_name}-logging"
  }
}