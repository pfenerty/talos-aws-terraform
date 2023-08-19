data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  tags = {
    Name = "${var.project_name}"
  }

  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "this" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  cidr_block = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "internet_gateway" {
  route_table_id         = aws_vpc.this.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_security_group" "internal" {
  name   = "${var.project_name}_internal"
  vpc_id = aws_vpc.this.id

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
  security_group_id            = aws_security_group.internal.id
  referenced_security_group_id = aws_security_group.internal.id
}

resource "aws_security_group" "control_plane" {
  name   = "${var.project_name}_talos_control_plane"
  vpc_id = aws_vpc.this.id

  ingress {
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = [var.kubernetes_api_allowed_cidr]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 50000
    to_port     = 50000
    cidr_blocks = [var.talos_api_allowed_cidr]
  }
}

resource "aws_lb" "this" {
  name               = var.project_name
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.this.*.id
}

resource "aws_lb_target_group" "this" {
  name        = var.project_name
  port        = "6443"
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}