data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Pinning availability_zones is strongly recommended. Left unset, the subnet
  # layout is derived from whatever AWS currently reports for the region, so
  # AWS adding an Availability Zone silently changes it.
  availability_zones = var.availability_zones != null ? var.availability_zones : data.aws_availability_zones.available.names

  # Keyed by Availability Zone rather than by position. With count, the list
  # index was the resource address, so an AZ appearing or disappearing shifted
  # every subnet after it and Terraform would destroy and recreate them - and
  # the cluster with them.
  subnet_cidrs = { for index, zone in local.availability_zones : zone => cidrsubnet(var.vpc_cidr, 8, index) }

  # Ordered by zone rather than by map key so that the list handed to the load
  # balancer and the compute module does not reorder between plans.
  subnet_ids = [for zone in local.availability_zones : aws_subnet.this[zone].id]
}

resource "aws_vpc" "this" {
  tags = merge(var.tags, {
    Name = var.project_name
  })

  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "this" {
  for_each = local.subnet_cidrs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key

  cidr_block = each.value

  # Karpenter picks the subnets it launches into by tag. The tag is inert when
  # Karpenter is not installed, so it is not gated on the post-install flag.
  tags = merge(var.tags, {
    Name = "${var.project_name}-${each.key}"

    "karpenter.sh/discovery" = var.project_name

    # How the AWS Load Balancer Controller and the in-tree cloud provider find
    # subnets to put internet-facing load balancers in.
    "kubernetes.io/role/elb" = "1"
  })
}

# AWS creates a default security group per VPC that allows all traffic between
# anything assigned to it. Nothing here uses it, but it exists and is
# attachable, so it is adopted with no rules rather than left open.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-default-unused"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = var.tags
}

resource "aws_route" "internet_gateway" {
  route_table_id         = aws_vpc.this.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Rules live in aws_vpc_security_group_{ingress,egress}_rule rather than in
# inline ingress/egress blocks. The two cannot be mixed on one security group:
# an inline block makes Terraform authoritative for every rule of that type, so
# it revokes whatever the standalone resources added, and the group flaps on
# every apply. This group had one of each.
resource "aws_security_group" "internal" {
  name        = "${var.project_name}-internal"
  description = "Node-to-node traffic for the ${var.project_name} cluster"
  vpc_id      = aws_vpc.this.id

  # Same discovery tag as the subnets: this is the security group Karpenter
  # attaches to the nodes it launches, and it is what lets them reach the
  # control plane.
  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.project_name
  })
}

resource "aws_vpc_security_group_ingress_rule" "talos_internal" {
  description                  = "All traffic between nodes in this cluster"
  ip_protocol                  = "-1"
  security_group_id            = aws_security_group.internal.id
  referenced_security_group_id = aws_security_group.internal.id
}

# One rule per address family: the standalone rule resources take a single CIDR
# each, where the inline block took a list.
resource "aws_vpc_security_group_egress_rule" "internal_ipv4" {
  description       = "Outbound IPv4, for image pulls and the AWS APIs"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.internal.id
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "internal_ipv6" {
  description       = "Outbound IPv6, for image pulls and the AWS APIs"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.internal.id
  cidr_ipv6         = "::/0"
}

# No egress rules: control plane nodes carry the internal group as well, and
# that is what grants them outbound access.
resource "aws_security_group" "control_plane" {
  name        = "${var.project_name}-talos-control-plane"
  description = "External API access to the ${var.project_name} control plane"
  vpc_id      = aws_vpc.this.id

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_api" {
  description       = "Kubernetes API"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  security_group_id = aws_security_group.control_plane.id
  cidr_ipv4         = var.kubernetes_api_allowed_cidr
}

resource "aws_vpc_security_group_ingress_rule" "talos_api" {
  description       = "Talos API"
  ip_protocol       = "tcp"
  from_port         = 50000
  to_port           = 50000
  security_group_id = aws_security_group.control_plane.id
  cidr_ipv4         = var.talos_api_allowed_cidr
}

# One load balancer node per subnet, and AWS bills a public IPv4 address for
# each of them. That is the hidden cost of leaving var.availability_zones
# unset: in a six-zone region this is six addresses rather than the two or
# three a control plane actually needs. See "Cost" in the README.
resource "aws_lb" "this" {
  name               = var.project_name
  internal           = false
  load_balancer_type = "network"

  # Billed: traffic a load balancer node forwards to a target in another zone
  # is inter-AZ transfer, charged in both directions. Left on because it is
  # what keeps the API reachable when the zone a client resolved to holds no
  # healthy control plane node - which is the normal state of affairs with
  # control_plane_nodes = 1 and subnets in every zone. Turning it off is only
  # safe with a control plane node in every subnet this balancer spans.
  #
  # For port 6443 the volume is small either way: this carries API traffic,
  # not workload traffic.
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  subnets = local.subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = var.project_name
  port        = "6443"
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  tags = var.tags
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
