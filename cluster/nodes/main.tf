resource "aws_launch_configuration" "launch_configuration" {
  name                        = "${var.project_name}_talos_${var.node_type}"
  image_id                    = data.aws_ami.talos.id
  instance_type               = var.instance_type
  user_data                   = var.user_data
  security_groups             = var.security_groups
  associate_public_ip_address = true
}

resource "aws_autoscaling_group" "autoscaling_group" {
  name                 = "${var.project_name}_talos_${var.node_type}"
  launch_configuration = aws_launch_configuration.launch_configuration.name
  min_size             = var.min_nodes
  max_size             = var.max_nodes
  vpc_zone_identifier  = var.subnets

  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}