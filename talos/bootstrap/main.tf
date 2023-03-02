resource "talos_machine_bootstrap" "talos_bootstrap" {
  talos_config = var.talos_config
  endpoint     = var.control_plane_ip
  node         = var.control_plane_ip
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  talos_config = var.talos_config
  endpoint     = var.control_plane_ip
  node         = var.control_plane_ip
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kube_config
  filename = "kubeconfig"
}