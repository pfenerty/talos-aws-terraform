output "control_plane_public_ips" {
  value = module.control_plane_nodes.*.public_ip
}

output "load_balancer_dns" {
  value = module.elb_k8s_elb.elb_dns_name
}