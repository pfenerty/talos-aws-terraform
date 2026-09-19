data "aws_partition" "current" {}

# Karpenter drains a node when EC2 tells it the instance is going away. EC2
# reports that through EventBridge, which is fanned into an SQS queue the
# controller polls.
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.project_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
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

  # The event keys are HCL identifiers, so they are snake_case; the rule names
  # they end up in are not, hence the replace.
  name = "${var.project_name}-karpenter-${replace(each.key, "_", "-")}"

  lifecycle {
    # EventBridge caps rule names at 64 characters and the longest key here
    # spends 44 of them, so a project_name the load balancer would accept can
    # still overflow this. Only reached when Karpenter is enabled, which is the
    # only time this module is instantiated.
    precondition {
      condition     = length("${var.project_name}-karpenter-${replace(each.key, "_", "-")}") <= 64
      error_message = "project_name is too long for the Karpenter interruption rule names: EventBridge allows 64 characters and the longest of these needs 44 on top of project_name, leaving 20."
    }
  }

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption

  rule = each.value.name
  arn  = aws_sqs_queue.interruption.arn
}

# Karpenter's identity: a role it assumes with its own service account token.
#
# The upstream controller policy is unchanged by that - it is the same set of
# EC2, pricing and SQS grants either way - but the principal is now a role
# scoped to one service account rather than an IAM user with a key pair that
# lived in Terraform state and in a Kubernetes secret.
module "role" {
  source = "../irsa-role"

  name            = "${var.project_name}-karpenter"
  service_account = "karpenter"
  policy = templatefile("${path.module}/iam.json.tmpl", {
    partition     = data.aws_partition.current.partition,
    region        = var.region,
    account_id    = var.aws_account_id,
    project_name  = var.project_name,
    node_role_arn = var.node_iam_role_arn,
    queue_arn     = aws_sqs_queue.interruption.arn
  })
  oidc = var.oidc
  tags = var.tags
}

# Consumed by the Karpenter HelmRelease, EC2NodeClass and NodePool in the Flux
# bootstrap repository. node-user-data is the Talos machine config the nodes
# boot from; it is multi-line, so it has to reach the EC2NodeClass through a
# HelmRelease valuesFrom targetPath rather than Flux postBuild substitution,
# which is a plain string replace and would break the YAML indentation.
#
# In flux-system rather than kube-system because valuesFrom resolves secrets
# in the HelmRelease's namespace.
resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = "karpenter-config"
    namespace = "flux-system"
  }

  data = {
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

    # The NodePool's requirements, rather than the EC2NodeClass's. Both are
    # Terraform's to decide: the architecture has to agree with the AMI pinned
    # above, and the capacity types are what decide whether elastic capacity is
    # billed at spot or on-demand rates.
    #
    # Comma-separated because a Secret's values are strings; the NodePool
    # splits it. Karpenter's own NodePool schema takes a list, so the Flux
    # repository does the split rather than passing this through verbatim.
    node-architecture = var.node_architecture
    capacity-types    = join(",", var.capacity_types)
  }
}

# Read by the controller through `envFrom`. Separate from the secret above,
# and in the controller's own namespace, because an environment variable has
# to come from an object in the pod's namespace - `valuesFrom` resolves in the
# HelmRelease's.
resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = "karpenter-aws-config"
    namespace = "kube-system"
  }

  data = {
    AWS_REGION                  = var.region
    AWS_ROLE_ARN                = module.role.role_arn
    AWS_WEB_IDENTITY_TOKEN_FILE = var.token_path
  }
}
