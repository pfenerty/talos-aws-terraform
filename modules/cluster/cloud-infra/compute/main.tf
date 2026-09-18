data "aws_ami" "this" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-amd64$"
}

# The control plane role grants nothing, deliberately. Its only consumer was
# the AWS cloud controller manager, which now authenticates with IRSA - a web
# identity role it assumes with a projected service account token, scoped to
# its own service account. The role and instance profile stay because an
# instance profile is how a node would ever get AWS credentials at all, and
# leaving an empty one attached makes it obvious that the absence is
# deliberate rather than forgotten.
#
# Nothing on a control plane node needs the AWS API. Talos reads instance
# metadata, which is not IAM-gated, and the control plane images come from
# public registries rather than ECR.
resource "aws_iam_role" "control_plane_assume_role" {
  name = "${var.project_name}-control-plane-assume-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.project_name}-control-plane"
  role = aws_iam_role.control_plane_assume_role.name

  tags = var.tags
}

resource "aws_launch_template" "control_plane" {
  name_prefix   = "${var.project_name}-control-plane"
  image_id      = data.aws_ami.this.id
  instance_type = var.control_plane_instance_type

  # Launch templates require user data to be base64 encoded; launch
  # configurations accepted it raw.
  user_data = base64encode(var.control_plane_machine_config)

  iam_instance_profile {
    name = aws_iam_instance_profile.control_plane.name
  }

  # Public IP assignment is only available via network_interfaces on a
  # launch template, which is also where security groups must go: the
  # top-level vpc_security_group_ids cannot be combined with it.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.control_plane_security_group_id, var.internal_security_group_id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"

    # 1, so that a pod cannot reach the metadata service at all: a packet
    # leaving a pod's network namespace has already spent a hop by the time
    # it gets here, and is dropped. Only processes on the host - Talos and
    # the kubelet - can read it.
    #
    # This is the setting, not a network policy, that makes IRSA worth having:
    # a role scoped to one service account is no constraint at all while any
    # pod can ask the metadata service for the node's credentials instead.
    #
    # It requires that nothing in a pod reads instance metadata. The cloud
    # controller manager is given its region and VPC in a cloud config file,
    # and the EBS CSI node plugin is set to read its metadata from the
    # Kubernetes API - both in the Flux bootstrap repository. A workload added
    # later that expects IMDS will fail here.
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = data.aws_ami.this.root_device_name

    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]
    content {
      resource_type = tag_specifications.value
      tags          = var.tags
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "control_plane" {
  name = "${var.project_name}-control-plane"
  launch_template {
    id      = aws_launch_template.control_plane.id
    version = aws_launch_template.control_plane.latest_version
  }
  min_size = var.control_plane_nodes

  # One above desired so an instance refresh has somewhere to put the
  # replacement before it takes the old node away.
  max_size            = var.control_plane_nodes + 1
  desired_capacity    = var.control_plane_nodes
  vpc_zone_identifier = var.subnets

  lifecycle {
    ignore_changes        = [load_balancers, target_group_arns]
    create_before_destroy = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
    }
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.control_plane.name
  lb_target_group_arn    = var.load_balancer_target_group_arn
}

resource "aws_iam_role" "worker_assume_role" {
  name = "${var.project_name}-worker-assume-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "worker" {
  name        = "${var.project_name}-worker-cloud-controller"
  description = "Worker permissions for cloud controller"

  policy = file("${path.module}/worker.policy.json")

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.worker_assume_role.name
  policy_arn = aws_iam_policy.worker.arn
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.project_name}-worker"
  role = aws_iam_role.worker_assume_role.name

  tags = var.tags
}

resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-worker"
  image_id      = data.aws_ami.this.id
  instance_type = var.worker_instance_type

  # Launch templates require user data to be base64 encoded; launch
  # configurations accepted it raw.
  user_data = base64encode(var.worker_machine_config)

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  # Public IP assignment is only available via network_interfaces on a
  # launch template, which is also where security groups must go: the
  # top-level vpc_security_group_ids cannot be combined with it.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.internal_security_group_id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"

    # 1, so that a pod cannot reach the metadata service at all: a packet
    # leaving a pod's network namespace has already spent a hop by the time
    # it gets here, and is dropped. Only processes on the host - Talos and
    # the kubelet - can read it.
    #
    # This is the setting, not a network policy, that makes IRSA worth having:
    # a role scoped to one service account is no constraint at all while any
    # pod can ask the metadata service for the node's credentials instead.
    #
    # It requires that nothing in a pod reads instance metadata. The cloud
    # controller manager is given its region and VPC in a cloud config file,
    # and the EBS CSI node plugin is set to read its metadata from the
    # Kubernetes API - both in the Flux bootstrap repository. A workload added
    # later that expects IMDS will fail here.
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = data.aws_ami.this.root_device_name

    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]
    content {
      resource_type = tag_specifications.value
      tags          = var.tags
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  name = "${var.project_name}-workers"
  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }
  min_size            = var.worker_nodes_min
  max_size            = var.worker_nodes_max
  desired_capacity    = var.worker_nodes_min
  vpc_zone_identifier = var.subnets

  lifecycle {
    ignore_changes        = [load_balancers, target_group_arns]
    create_before_destroy = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
    }
  }
}
