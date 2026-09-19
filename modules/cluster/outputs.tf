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

output "control_plane_ami_id" {
  value       = module.compute.control_plane_ami_id
  description = "AMI the control plane nodes boot from."
}

output "worker_ami_id" {
  value       = module.compute.worker_ami_id
  description = "AMI the worker nodes boot from, and the one Karpenter launches with."
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

# Ordered by instance ID, like everything else derived from the instance data
# sources, so that a refresh that returns the same nodes in a different order
# does not show up as a change.
output "control_plane_public_ips" {
  value       = local.control_plane_public_ips
  description = "Public addresses of the control plane nodes, ordered by instance ID. The Talos API listens here; node addresses themselves are private."
}

output "control_plane_private_ips" {
  value       = local.control_plane_private_ips
  description = "Private addresses of the control plane nodes, ordered by instance ID, which is how Talos identifies them."
}

output "worker_private_ips" {
  value       = local.worker_private_ips
  description = "Private addresses of the baseline worker nodes, ordered by instance ID."
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
    project_name = var.project_name
    region       = var.region
    pod_cidr     = var.pod_cidr

    # Published into the cluster for the upgrade controller to read. These are
    # the same values that select the AMI and render the machine config, so
    # the controller and the launch templates cannot end up naming different
    # versions - which they would if the Flux repository restated them.
    talos_version      = var.talos_version
    kubernetes_version = var.kubernetes_version

    cluster_endpoint                = "https://${module.networking.load_balancer_dns}:443"
    load_balancer_dns               = module.networking.load_balancer_dns
    client_configuration            = module.talos_config.client_configuration
    control_plane_public_ips        = local.control_plane_public_ips
    control_plane_private_ips       = local.control_plane_private_ips
    worker_private_ips              = local.worker_private_ips
    node_count                      = var.control_plane_nodes + var.worker_nodes_min
    worker_instance_profile_name    = module.compute.worker_instance_profile_name
    worker_iam_role_arn             = module.compute.worker_iam_role_arn
    worker_ami_id                   = module.compute.worker_ami_id
    worker_architecture             = module.compute.worker_architecture
    karpenter_worker_machine_config = module.talos_config.karpenter_worker_machine_config

    # IRSA. The bucket is created by the bootstrap module, but named here:
    # the issuer URL is in the machine config, which is rendered here.
    oidc_bucket     = local.oidc_bucket
    oidc_issuer_url = local.oidc_issuer_url

    # The cluster's own network facts, which the cloud controller manager
    # needs in its cloud config once it can no longer read them from the
    # instance metadata service.
    vpc_id    = module.networking.vpc_id
    subnet_id = module.networking.public_subnets[0]

    # Admin credentials, for reading the API server's OIDC discovery
    # documents over mutual TLS.
    kubernetes_client_configuration = local.kubernetes_client_configuration

    tags = local.tags
  }
}

output "oidc_issuer_url" {
  value       = local.oidc_issuer_url
  description = "URL the API server names as the issuer of its service account tokens, and where the bootstrap module publishes the OIDC discovery documents. Registered with AWS as an IAM identity provider."
}
