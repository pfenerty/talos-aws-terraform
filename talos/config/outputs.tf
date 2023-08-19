output "talosconfig" {
  value = talos_client_configuration.talosconfig.talos_config
}

output "control_plane_machine_config" {
  value = talos_machine_configuration_controlplane.machineconfig_cp.machine_config
}

output "worker_machine_config" {
  value = talos_machine_configuration_worker.machineconfig_worker.machine_config
}