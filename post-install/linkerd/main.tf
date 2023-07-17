resource "tls_private_key" "linkerd" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "linkerd" {
  private_key_pem = tls_private_key.linkerd.private_key_pem

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  validity_period_hours = 12

  allowed_uses      = ["any_extended"]
  is_ca_certificate = true
}

resource "kubernetes_namespace" "linkerd" {
  metadata {
    name = "linkerd"

    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_secret" "linkerd_trust_anchor_flux" {
  type = "kubernetes.io/tls"

  metadata {
    name      = "linkerd-trust-anchor"
    namespace = "flux-system"
  }

  data = {
    "tls.crt" = tls_self_signed_cert.linkerd.cert_pem
    "tls.key" = ""
  }
}

resource "kubernetes_secret" "linkerd_trust_anchor_linkerd" {
  type = "kubernetes.io/tls"

  metadata {
    name      = "linkerd-trust-anchor"
    namespace = "linkerd"
  }

  data = {
    "tls.crt" = tls_self_signed_cert.linkerd.cert_pem
    "tls.key" = tls_private_key.linkerd.private_key_pem
  }
}