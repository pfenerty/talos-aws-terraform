resource "random_uuid" "cluster_flux_id" {}

resource "flux_bootstrap_git" "this" {
  path = "clusters/${random_uuid.cluster_flux_id.result}"
}

module "ebs" {
  source = "./ebs"
  project_name = var.project_name
}

module "linkerd" {
  source = "./linkerd"

  depends_on = [ flux_bootstrap_git.this ]
}