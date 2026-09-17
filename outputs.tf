output "cluster_endpoint" {
  value       = "https://${module.networking.load_balancer_dns}:443"
  description = "Kubernetes API endpoint, and the Talos cluster endpoint."
}

output "load_balancer_dns" {
  value       = module.networking.load_balancer_dns
  description = "DNS name of the network load balancer in front of the control plane."
}

output "vpc_id" {
  value       = module.networking.vpc_id
  description = "ID of the VPC the cluster runs in."
}

output "subnet_ids" {
  value       = module.networking.public_subnets
  description = "Subnets the cluster runs in, ordered by Availability Zone."
}

output "availability_zones" {
  value       = module.networking.availability_zones
  description = "Availability Zones the subnets were created in. Pin var.availability_zones to this list to stop the layout moving."
}

output "control_plane_autoscaling_group_name" {
  value       = module.compute.control_plane_autoscaling_group_name
  description = "Name of the control plane autoscaling group."
}

output "talos_ami_id" {
  value       = module.compute.talos_ami_id
  description = "AMI the cluster nodes boot from."
}

# Paths rather than contents: both files hold credentials, and printing them
# through an output puts them in anything that captures Terraform's stdout.
output "kubeconfig_path" {
  value       = "${path.root}/kubeconfig"
  description = "Path to the generated kubeconfig. Contains cluster credentials."
}

output "talosconfig_path" {
  value       = "${path.root}/talosconfig"
  description = "Path to the generated talosconfig. Contains cluster credentials."
}
