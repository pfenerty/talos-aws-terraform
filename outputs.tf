output "cluster_endpoint" {
  value       = module.cluster.cluster_endpoint
  description = "Kubernetes API endpoint, and the Talos cluster endpoint."
}

output "load_balancer_dns" {
  value       = module.cluster.load_balancer_dns
  description = "DNS name of the network load balancer in front of the control plane."
}

output "vpc_id" {
  value       = module.cluster.vpc_id
  description = "ID of the VPC the cluster runs in."
}

output "subnet_ids" {
  value       = module.cluster.subnet_ids
  description = "Subnets the cluster runs in, ordered by Availability Zone."
}

output "availability_zones" {
  value       = module.cluster.availability_zones
  description = "Availability Zones the subnets were created in. Pin var.availability_zones to this list to stop the layout moving."
}

output "control_plane_autoscaling_group_name" {
  value       = module.cluster.control_plane_autoscaling_group_name
  description = "Name of the control plane autoscaling group."
}

output "control_plane_ami_id" {
  value       = module.cluster.control_plane_ami_id
  description = "AMI the control plane nodes boot from."
}

output "worker_ami_id" {
  value       = module.cluster.worker_ami_id
  description = "AMI the worker nodes boot from, and the one Karpenter launches with."
}

output "kubeconfig" {
  value       = module.cluster.kubeconfig
  sensitive   = true
  description = "Admin kubeconfig for the cluster. Contains cluster credentials: `terraform output -raw kubeconfig > ~/.kube/talos` rather than letting it into a log."
}

output "talosconfig" {
  value       = module.cluster.talosconfig
  sensitive   = true
  description = "Talos client configuration. Contains cluster credentials."
}

output "flux_path" {
  value       = module.bootstrap.flux_path
  description = "Path inside the Flux bootstrap repository this cluster syncs from."
}
