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

# The credentials themselves, not paths to them. A caller needs these to
# configure the kubernetes, helm and flux providers the bootstrap module
# runs under, and there is no file to point at unless config_output_path
# was set.
output "kubeconfig" {
  value       = module.talos_bootstrap.kubeconfig
  sensitive   = true
  description = "Admin kubeconfig for the cluster. Contains cluster credentials."
}

output "talosconfig" {
  value       = module.talos_config.talosconfig
  sensitive   = true
  description = "Talos client configuration. Contains cluster credentials."
}

output "client_configuration" {
  value       = module.talos_config.client_configuration
  sensitive   = true
  description = "Talos client certificates, for the Talos provider's own data sources and resources."
}

output "control_plane_public_ips" {
  value       = data.aws_instances.control_plane_instances.public_ips
  description = "Public addresses of the control plane nodes. The Talos API listens here; node addresses themselves are private."
}

output "control_plane_private_ips" {
  value       = data.aws_instances.control_plane_instances.private_ips
  description = "Private addresses of the control plane nodes, which is how Talos identifies them."
}

output "worker_private_ips" {
  value       = data.aws_instances.worker_instances.private_ips
  description = "Private addresses of the baseline worker nodes."
}

output "node_count" {
  value       = var.control_plane_nodes + var.worker_nodes_min
  description = "Number of nodes the cluster is created with, before Karpenter provisions anything. Used to size add-ons whose replica counts cannot exceed the number of nodes."
}

# Everything the bootstrap module needs from this one, as a single object, so
# the two are wired together with one argument rather than a dozen.
output "bootstrap_inputs" {
  description = "Cluster facts consumed by the bootstrap module. Pass straight to its `cluster` variable."
  sensitive   = true
  value = {
    project_name                    = var.project_name
    region                          = var.region
    pod_cidr                        = var.pod_cidr
    cluster_endpoint                = "https://${module.networking.load_balancer_dns}:443"
    load_balancer_dns               = module.networking.load_balancer_dns
    client_configuration            = module.talos_config.client_configuration
    control_plane_public_ips        = data.aws_instances.control_plane_instances.public_ips
    control_plane_private_ips       = data.aws_instances.control_plane_instances.private_ips
    worker_private_ips              = data.aws_instances.worker_instances.private_ips
    node_count                      = var.control_plane_nodes + var.worker_nodes_min
    worker_instance_profile_name    = module.compute.worker_instance_profile_name
    worker_iam_role_arn             = module.compute.worker_iam_role_arn
    worker_ami_id                   = module.compute.talos_ami_id
    karpenter_worker_machine_config = module.talos_config.karpenter_worker_machine_config
  }
}
