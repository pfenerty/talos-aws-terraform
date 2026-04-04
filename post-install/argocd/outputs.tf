output "argocd_server_url" {
  description = "Argo CD server LoadBalancer URL"
  value       = var.git_url != "" || var.admin_password_hash != "" ? "http://<check-with-kubectl>" : "Run: kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "argocd_admin_password_command" {
  description = "Command to get Argo CD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
