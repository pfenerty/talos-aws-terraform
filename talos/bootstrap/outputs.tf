output "kubeconfig" {
  sensitive = true
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
}