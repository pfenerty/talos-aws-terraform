resource "talos_machine_bootstrap" "talos_bootstrap" {
  talos_config = var.talos_config
  endpoint     = var.public_ip
  node         = var.private_ip
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  talos_config = var.talos_config
  endpoint     = var.public_ip
  node         = var.private_ip

  depends_on = [
    talos_machine_bootstrap.talos_bootstrap
  ]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kube_config
  filename = "kubeconfig"
}