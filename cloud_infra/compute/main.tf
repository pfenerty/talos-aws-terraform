data "aws_ami" "this" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-amd64$"
}

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
}

resource "aws_iam_policy" "control_plane" {
  name        = "${var.project_name}-control-plane-cloud-controller"
  description = "Control Plane permissions for cloud controller"

  policy = file("${path.module}/control-plane.policy.json")
}

resource "aws_iam_role_policy_attachment" "control_plane" {
  role       = aws_iam_role.control_plane_assume_role.name
  policy_arn = aws_iam_policy.control_plane.arn
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.project_name}-control-plane"
  role = aws_iam_role.control_plane_assume_role.name
}

resource "aws_launch_configuration" "control_plane" {
  name_prefix                 = "${var.project_name}_control_plane"
  image_id                    = data.aws_ami.this.id
  instance_type               = var.control_plane_instance_type
  user_data                   = var.control_plane_machine_config
  security_groups             = [var.control_plane_security_group_id, var.internal_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.control_plane.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 100
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "control_plane" {
  name                 = "${var.project_name}_control_plane"
  launch_configuration = aws_launch_configuration.control_plane.name
  min_size             = var.control_plane_nodes
  max_size             = var.control_plane_nodes
  desired_capacity     = var.control_plane_nodes
  vpc_zone_identifier  = var.subnets

  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
    create_before_destroy = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.project_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
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
}

resource "aws_iam_policy" "worker" {
  name        = "${var.project_name}-worker-cloud-controller"
  description = "Worker permissions for cloud controller"

  policy = file("${path.module}/worker.policy.json")
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.worker_assume_role.name
  policy_arn = aws_iam_policy.worker.arn
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.project_name}-worker"
  role = aws_iam_role.worker_assume_role.name
}

resource "aws_launch_configuration" "worker" {
  name_prefix                 = "${var.project_name}_worker"
  image_id                    = data.aws_ami.this.id
  instance_type               = var.worker_instance_type
  user_data                   = var.worker_machine_config
  security_groups             = [var.internal_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.worker.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 100
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  name                 = "${var.project_name}_workers"
  launch_configuration = aws_launch_configuration.worker.name
  min_size             = var.worker_nodes_min
  max_size             = var.worker_nodes_max
  desired_capacity     = var.worker_nodes_min
  vpc_zone_identifier  = var.subnets

  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
    create_before_destroy = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.project_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.project_name}"
    value               = ""
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 30
    }
  }
}