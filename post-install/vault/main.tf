resource "aws_dynamodb_table" "this" {
  name           = "${var.project_name}-vault-data"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "Path"
  range_key      = "Key"

  attribute {
    name = "Path"
    type = "S"
  }

  attribute {
    name = "Key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_iam_user_policy" "dynamodb" {
  name = "${var.project_name}-vault-dynamodb"
  user = aws_iam_user.this.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "dynamodb:DescribeLimits",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource",
          "dynamodb:DescribeReservedCapacityOfferings",
          "dynamodb:DescribeReservedCapacity",
          "dynamodb:ListTables",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:CreateTable",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:GetRecords",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
          "dynamodb:DescribeTable",
        ],
        "Effect" : "Allow",
        "Resource" : [aws_dynamodb_table.this.arn]
      }
    ]
  })
}

resource "aws_iam_user_policy" "kms" {
  name  = "${var.project_name}-vault-kms"
  user  = aws_iam_user.this.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
        ],
        "Effect" : "Allow",
        "Resource" : [aws_kms_key.this.arn]
      }
    ]
  })
}

resource "aws_kms_key" "this" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_iam_user" "this" {
  name = "${var.project_name}-vault"
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = "vault"
  }
}

resource "kubernetes_secret" "creds" {
  metadata {
    name      = "aws-creds"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    access_key = aws_iam_access_key.this.id
    secret_key = aws_iam_access_key.this.secret
  }
}

resource "kubernetes_secret" "storage" {
  metadata {
    name      = "storage-config"
    namespace = "flux-system"
  }

  data = {
    "config" = templatefile("${path.module}/config.tmpl", {
      region = var.region,
      dynamodb_table = aws_dynamodb_table.this.name,
      kms_key_id = aws_kms_key.this.id
    })
  }
}