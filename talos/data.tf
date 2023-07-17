data "helm_template" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  namespace  = "kube-system"
  chart      = "cilium"
  version    = var.cilium_version

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
    value = var.cilium_proxy_replacement ? "strict" : "disabled"
  }

  set {
    name  = "k8sServiceHost"
    value = var.load_balancer_dns
  }

  set {
    name  = "k8sServicePort"
    value = 443
  }

  set {
    name  = "hubble.relay.enabled"
    value = var.cilium_enable_hubble
  }

  set {
    name  = "hubble.ui.enabled"
    value = var.cilium_enable_hubble
  }

  set {
    name = "socketLB.hostNamespaceOnly"
    value = "true"
  }
}