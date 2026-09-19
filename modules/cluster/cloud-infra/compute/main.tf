# One AMI per role rather than one for the cluster, because the two roles can
# run on different architectures: a Graviton control plane in front of x86
# workers is a reasonable thing to want while a workload is still being ported,
# and the reverse is what an incremental migration looks like on the way there.
#
# Sidero publishes one image per architecture per region, and the architecture
# has to agree with the instance type or the instance fails to boot with
# nothing useful in the console. Nothing here can check that pairing - the
# instance type is a free string and AWS is the only thing that knows what it
# runs on - so the architecture variables are constrained to the two values
# Sidero actually publishes and the pairing is left to the caller.
data "aws_ami" "control_plane" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-${var.control_plane_architecture}$"
}

data "aws_ami" "worker" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-${var.worker_architecture}$"
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
  image_id      = data.aws_ami.control_plane.id
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

  # gp3 is left at its included baseline of 3000 IOPS and 125 MB/s: both are
  # free at any volume size, and provisioning above them is billed separately.
  # Nothing here needs more, and an etcd that does wants a bigger instance
  # rather than a faster root disk.
  block_device_mappings {
    device_name = data.aws_ami.control_plane.root_device_name

    ebs {
      volume_size           = var.control_plane_root_volume_size
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

  # A launch template change is what starts an instance refresh, and the
  # machine config is in the launch template - so with this on, editing a
  # config patch replaces every control plane node to deliver it. It is off
  # by default because the config module applies changes to running nodes
  # over the Talos API instead. See "Machine config updates" in the README.
  #
  # What that leaves behind is the AMI: a talos_version bump writes a new
  # launch template too, and there is no in-place upgrade path for it here,
  # so new nodes boot the new image and existing ones stay on the old one
  # until they are rolled deliberately.
  dynamic "instance_refresh" {
    for_each = var.instance_refresh ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = 100
        max_healthy_percentage = 200
      }
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
  image_id      = data.aws_ami.worker.id
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

  # Sized independently of the control plane: this is the disk container
  # images and ephemeral storage land on, so it is the one that grows with
  # what the cluster actually runs. See the note on gp3 baselines above.
  block_device_mappings {
    device_name = data.aws_ami.worker.root_device_name

    ebs {
      volume_size           = var.worker_root_volume_size
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

  # Off by default for the same reason as the control plane group above.
  dynamic "instance_refresh" {
    for_each = var.instance_refresh ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = 100
        max_healthy_percentage = 200
      }
    }
  }
}
