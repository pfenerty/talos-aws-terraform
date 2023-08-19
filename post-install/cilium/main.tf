resource "helm_release" "cilium" {
  name       = "kube-system-cilium"
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
    value = "strict"
  }

  set {
    name  = "k8sServiceHost"
    value = var.k8s_service_host
  }

  set {
    name  = "k8sServicePort"
    value = 443
  }

  set {
    name  = "encryption.enabled"
    value = "true"
  }

  set {
    name  = "encryption.type"
    value = "wireguard"
  }

  set {
    name  = "encryption.strictMode.enabled"
    value = "true"
  }
}

resource "tls_private_key" "hubble" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "hubble" {
  private_key_pem = tls_private_key.hubble.private_key_pem

  subject {
    common_name = "root.hubble.cluster.local"
  }

  validity_period_hours = 12

  allowed_uses      = ["any_extended"]
  is_ca_certificate = true
}

resource "kubernetes_secret" "hubble_trust_anchor" {
  type = "kubernetes.io/tls"

  metadata {
    name      = "hubble-trust-anchor"
    namespace = "kube-system"
  }

  data = {
    "tls.crt" = tls_self_signed_cert.hubble.cert_pem
    "tls.key" = tls_private_key.hubble.private_key_pem
  }
}