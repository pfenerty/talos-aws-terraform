# Bootstrapping is a once-per-cluster act: it initialises etcd, and running it
# again against a cluster that already has an etcd member fails. The addresses
# below name whichever control plane node the cluster module picked, and that
# node can be replaced - by an AMI change, a failed health check, a manual
# termination - which would otherwise change these arguments, replace this
# resource, and re-run the bootstrap against a live cluster.
#
# So they are read once, at create, and ignored afterwards. The stale address
# left in state is only ever used to decide whether to bootstrap again, and the
# answer to that is always no.
resource "talos_machine_bootstrap" "talos_bootstrap" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip

  lifecycle {
    ignore_changes = [endpoint, node]
  }
}

# Ignored for the same reason, less urgently: re-reading the kubeconfig from a
# different control plane node is harmless, but it issues a fresh admin
# certificate and churns every provider configured from it.
resource "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip

  lifecycle {
    ignore_changes = [endpoint, node]
  }

  depends_on = [
    talos_machine_bootstrap.talos_bootstrap
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  count = var.config_output_path != null ? 1 : 0

  content  = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename = "${var.config_output_path}/kubeconfig"
}
