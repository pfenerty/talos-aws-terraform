resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  
  timeout          = 600  # 10 minutes
  wait             = true
  wait_for_jobs    = true
  create_namespace = false
  
  atomic           = false  # Don't rollback on failure
  cleanup_on_fail  = false  # Keep resources for debugging

  values = [
    yamlencode({
      global = {
        # Remove problematic tolerations - let pods schedule normally
      }
      server = {
        extraArgs = [
          "--insecure" # For internal access; remove for production with proper TLS
        ]
        service = {
          type = "LoadBalancer"
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      controller = {
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      repoServer = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      dex = {
        enabled = false  # Disable Dex if not needed
      }
      configs = {
        secret = {
          argocdServerAdminPassword = var.admin_password_hash
        }
      }
    })
  ]
}

# Create Git repository secret if SSH key is provided
resource "kubernetes_secret" "git_repo" {
  count = var.git_ssh_key != "" ? 1 : 0

  metadata {
    name      = "git-repo-credentials"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.git_url
    sshPrivateKey = var.git_ssh_key
  }

  depends_on = [helm_release.argocd]
}

# Bootstrap application - points to your GitOps repo
resource "kubernetes_manifest" "bootstrap_app" {
  count = var.git_url != "" ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bootstrap"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_url
        targetRevision = var.git_branch
        path           = var.git_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.git_repo
  ]
}
