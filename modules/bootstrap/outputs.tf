# Read off the resource rather than off var.flux.enabled: the flux variable
# is sensitive as a whole because it carries the deploy key, and deriving the
# output from it would mark this path sensitive too. The path is a random
# UUID, not a secret.
output "flux_path" {
  value       = one(flux_bootstrap_git.this[*].path)
  description = "Path inside the Flux bootstrap repository this cluster syncs from."
}

output "cluster_healthy" {
  value       = data.talos_cluster_health.this.id
  description = "Set once the cluster has reported healthy. Depend on this to order work after the cluster is usable."
}
