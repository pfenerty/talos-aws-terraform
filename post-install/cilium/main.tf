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
    # These two lists are the chart defaults minus SYS_MODULE: Talos is
    # immutable and does not permit loading kernel modules, so granting it
    # is pointless. Re-check them against the chart's values.yaml on every
    # Cilium bump, since the defaults do gain entries (1.20 added SYSLOG to
    # ciliumAgent, deliberately not adopted here).
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
    # Cilium 1.20 replaced encryption.strictMode.enabled with separate
    # egress/ingress sub-keys. helm --set on a path the chart no longer
    # knows is silently accepted, so the old key would have quietly stopped
    # enforcing strict encryption.
    {
      name  = "encryption.strictMode.egress.enabled"
      value = "true"
    },
    {
      name  = "encryption.strictMode.egress.cidr"
      value = var.pod_cidr
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

resource "kubernetes_secret_v1" "hubble_trust_anchor" {
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