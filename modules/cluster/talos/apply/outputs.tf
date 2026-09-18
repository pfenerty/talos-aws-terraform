output "applied_nodes" {
  value       = [for apply in talos_machine_configuration_apply.this : apply.node]
  description = "Nodes the machine config was applied to, in the order it was applied."
}

# `staged_if_needing_reboot` resolves to `auto` or `staged` per node after a
# dry run. A node that resolved to `staged` is carrying a configuration it has
# not started using yet, and will not until it reboots, so this is the thing
# to look at after a config change that did not appear to do anything.
output "resolved_apply_modes" {
  value       = { for apply in talos_machine_configuration_apply.this : apply.node => apply.resolved_apply_mode }
  description = "The apply mode Talos actually used per node. `staged` means the configuration is on the node but does not take effect until it reboots."
}
