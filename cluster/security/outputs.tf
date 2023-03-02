output "all_sgid" {
  value = aws_security_group.all_nodes.id
}

output "control_plane_sgid" {
  value = aws_security_group.control_plane_node.id
}