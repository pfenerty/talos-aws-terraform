resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  namespace  = "kube-system"
  chart      = "cilium"
  version    = var.app_version

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  set {
    name  = "securityContext.privileged"
    value = "true"
  }

  set {
    name  = "kubeProxyReplacement"
    value = var.proxy_replacement ? "strict" : "disabled"
  }

  set {
    name  = "k8sServiceHost"
    value = var.k8s_service_host
  }

  set {
    name  = "k8sServicePort"
    value = var.k8s_service_port
  }

  set {
    name  = "hubble.relay.enabled"
    value = var.enable_hubble
  }

  set {
    name  = "hubble.ui.enabled"
    value = var.enable_hubble
  }
}