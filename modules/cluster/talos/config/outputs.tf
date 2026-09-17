output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "client_configuration" {
  value     = talos_machine_secrets.machine_secrets.client_configuration
  sensitive = true
}

output "control_plane_machine_config" {
  value     = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  sensitive = true
}

output "worker_machine_config" {
  value     = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  sensitive = true
}

output "karpenter_worker_machine_config" {
  value       = data.talos_machine_configuration.machineconfig_karpenter_worker.machine_configuration
  sensitive   = true
  description = "Worker machine config for nodes launched by Karpenter. Identical to worker_machine_config apart from the karpenter.sh/unregistered taint, and used as the EC2NodeClass user data."
}
