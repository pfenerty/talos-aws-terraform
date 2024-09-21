resource "talos_machine_bootstrap" "talos_bootstrap" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = var.client_configuration
  endpoint             = var.public_ip
  node                 = var.private_ip

  depends_on = [
    talos_machine_bootstrap.talos_bootstrap
  ]
}

resource "local_file" "kubeconfig" {
  content  = data.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename = "kubeconfig"
}