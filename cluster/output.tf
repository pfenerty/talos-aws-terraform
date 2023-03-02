output "control_plane_asg_name" {
  value = module.control_plane.autoscaling_group_name
}

output "load_balancer_dns" {
  value = module.load_balancer.dns
}