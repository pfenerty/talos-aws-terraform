data "aws_partition" "current" {}

# Karpenter drains a node when EC2 tells it the instance is going away. EC2
# reports that through EventBridge, which is fanned into an SQS queue the
# controller polls.
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.project_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        Sid    = "AllowEventBridgeToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.interruption.arn
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.interruption.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

locals {
  # The event types Karpenter knows how to act on. Anything else landing in the
  # queue is dropped by the controller, so the patterns are kept tight.
  interruption_events = {
    scheduled_change = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
    spot_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    instance_state_change = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
    capacity_reservation_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Capacity Reservation Instance Interruption Warning"
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name = "${var.project_name}-karpenter-${each.key}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption

  rule = each.value.name
  arn  = aws_sqs_queue.interruption.arn
}

# There is no OIDC provider in front of this cluster, so the controller
# authenticates with a static key pair the same way the other extras do.
resource "aws_iam_user" "this" {
  name = "${var.project_name}_karpenter"
}

resource "aws_iam_policy" "this" {
  name = "${var.project_name}_karpenter"
  policy = templatefile("${path.module}/iam.json.tmpl", {
    partition     = data.aws_partition.current.partition,
    region        = var.region,
    account_id    = var.aws_account_id,
    project_name  = var.project_name,
    node_role_arn = var.node_iam_role_arn,
    queue_arn     = aws_sqs_queue.interruption.arn
  })
}

resource "aws_iam_user_policy_attachment" "this" {
  user       = aws_iam_user.this.name
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

# Consumed by the Karpenter HelmRelease, EC2NodeClass and NodePool in the Flux
# bootstrap repository. node-user-data is the Talos machine config the nodes
# boot from; it is multi-line, so it has to reach the EC2NodeClass through a
# HelmRelease valuesFrom targetPath rather than Flux postBuild substitution,
# which is a plain string replace and would break the YAML indentation.
resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = "karpenter-config"
    namespace = "flux-system"
  }

  data = {
    access-key-id     = aws_iam_access_key.this.id
    secret-access-key = aws_iam_access_key.this.secret

    cluster-name       = var.project_name
    cluster-endpoint   = var.cluster_endpoint
    region             = var.region
    interruption-queue = aws_sqs_queue.interruption.name

    # Subnets and the internal security group are tagged with
    # karpenter.sh/discovery = <project name> by the networking module.
    discovery-tag         = var.project_name
    node-instance-profile = var.node_instance_profile_name
    node-ami-id           = var.node_ami_id
    node-user-data        = var.node_user_data
  }
}
