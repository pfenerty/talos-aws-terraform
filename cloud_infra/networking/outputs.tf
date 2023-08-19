output "load_balancer_dns" {
  value = aws_lb.this.dns_name
}

output "load_balancer_arn" {
  value = aws_lb.this.arn
}

output "load_balancer_target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

output "public_subnets" {
  value = aws_subnet.this.*.id
}

output "control_plane_security_group_id" {
  value = aws_security_group.control_plane.id
}

output "internal_security_group_id" {
  value = aws_security_group.internal.id
}