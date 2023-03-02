resource "aws_security_group" "all_nodes" {
  name   = "${var.project_name}_talos_all_nodes"
  vpc_id = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "talos_internal" {
  ip_protocol                  = -1
  security_group_id            = aws_security_group.all_nodes.id
  referenced_security_group_id = aws_security_group.all_nodes.id
}

resource "aws_security_group" "control_plane_node" {
  name   = "${var.project_name}_talos_control_plane"
  vpc_id = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 50000
    to_port     = 50001
    cidr_blocks = [var.admin_cidr]
  }
}