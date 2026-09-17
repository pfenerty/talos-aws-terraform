resource "talos_machine_bootstrap" "talos_bootstrap" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip

  depends_on = [
    talos_machine_bootstrap.talos_bootstrap
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  count = var.config_output_path != null ? 1 : 0

  content  = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename = "${var.config_output_path}/kubeconfig"
}
