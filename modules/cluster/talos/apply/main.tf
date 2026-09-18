# The second of the two channels a machine config reaches a node by.
#
# The first is user data. The launch templates carry the rendered config, and
# that is what a node reads at first boot - which makes it the only channel a
# node the autoscaling group brings up on its own ever sees. A scale-out, a
# replacement after a failed health check, a Karpenter node: all of them join
# the cluster correctly with nothing to run by hand, because the config is
# already sitting in their user data.
#
# Talos reads user data once. Afterwards the machine's configuration lives in
# its STATE partition, and a running node never learns that Terraform rendered
# something different. So user data alone means a config change only reaches
# the fleet by replacing every node in it.
#
# This module applies the same rendered config to the nodes that are already
# running, over the Talos API, which is what `talosctl apply-config` does and
# what Talos expects. Between the two channels a config change reconfigures
# the cluster rather than rebuilding it, and a node that appears later still
# comes up configured.
#
# Nodes are addressed by count rather than for_each because their addresses
# come from a data source that reads after the autoscaling groups apply: on
# the first apply they are unknown at plan time, and for_each keys may not be.
# var.node_count is the configured size of the group, which is known, and
# var.nodes is ordered by instance ID upstream so that an index names the same
# machine between plans.
locals {
  # element() rejects an empty list, and an empty list is exactly what the
  # precondition below exists to report. Padding keeps the failure on the
  # precondition, whose message says what to do about it, rather than on a
  # function argument error that does not mention the autoscaling group.
  nodes     = length(var.nodes) > 0 ? var.nodes : [""]
  endpoints = length(var.endpoints) > 0 ? var.endpoints : [""]
}

resource "talos_machine_configuration_apply" "this" {
  count = var.node_count

  client_configuration        = var.client_configuration
  machine_configuration_input = var.machine_configuration
  node                        = element(local.nodes, count.index)

  # element() rather than an index, so a shorter list wraps and a single
  # endpoint serves every node. Control plane nodes are reached at their own
  # public addresses; workers have no Talos API ingress of their own and are
  # reached through a control plane node, which routes to them over the
  # internal network.
  endpoint = element(local.endpoints, count.index)

  apply_mode = var.apply_mode

  lifecycle {
    precondition {
      condition     = length(var.nodes) > 0
      error_message = "No running instances were found for this node group, so there is nothing to apply the machine config to. The autoscaling group may still be launching, or its instances may be failing to start."
    }
  }
}
