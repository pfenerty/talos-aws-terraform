output "talosconfig" {
  value = data.talos_client_configuration.talosconfig.talos_config
}

output "client_configuration" {
  value = talos_machine_secrets.machine_secrets.client_configuration
}

output "control_plane_machine_config" {
  value = data.talos_machine_configuration.machineconfig_cp.machine_configuration
}

output "worker_machine_config" {
  value = data.talos_machine_configuration.machineconfig_worker.machine_configuration
}