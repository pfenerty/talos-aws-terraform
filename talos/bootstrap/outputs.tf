output "kubeconfig" {
  value = talos_cluster_kubeconfig.kubeconfig.kube_config
}