output "control_plane_nodes" {
  value = module.control_plane_nodes
}

output "worker_nodes" {
  value = module.worker_nodes
}

output "load_balancer_dns" {
  value = module.elb_k8s_elb.elb_dns_name
}

output "availability_zone" {
  value = data.aws_availability_zones.available.names[0]
}