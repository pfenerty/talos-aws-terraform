resource "helm_release" "cilium" {
  name       = "kube-system-cilium"
  repository = "https://helm.cilium.io"
  namespace  = "kube-system"
  chart      = "cilium"
  version    = var.cilium_version

  set = [
    {
      name  = "ipam.mode"
      value = "kubernetes"
    },
    {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    },
    {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    },
    {
      name  = "cgroup.autoMount.enabled"
      value = "false"
    },
    {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "k8sServiceHost"
      value = "localhost"
    },
    {
      name  = "k8sServicePort"
      value = 7445
    },
    {
      name  = "encryption.enabled"
      value = "true"
    },
    {
      name  = "encryption.type"
      value = "wireguard"
    },
    {
      name  = "encryption.strictMode.enabled"
      value = "true"
    },
  ]
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