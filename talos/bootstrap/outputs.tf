output "kubeconfig" {
  value = data.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
}