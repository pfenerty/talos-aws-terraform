# The bootstrap install only. Its job is to get nodes to Ready so that
# CoreDNS, Flux and everything after them can schedule; the full Cilium
# configuration - WireGuard transparent encryption in strict mode, Hubble -
# is applied afterwards by the Cilium HelmRelease in the Flux bootstrap
# repository, which adopts this release.
#
# Two consequences follow, and both are deliberate:
#
#   - There is a window between this install and Flux's first reconcile in
#     which pod-to-pod traffic is not encrypted. It lasts as long as Flux
#     takes to come up.
#   - `ignore_changes = all` means Terraform creates this release and then
#     never touches it again. Bumping cilium_bootstrap_version changes what a
#     *new* cluster installs and does nothing to an existing one, because on
#     an existing one Cilium belongs to Flux. Upgrade it there.
#
# Everything set below is required for Cilium to run on Talos at all, so the
# minimal install is the full one minus encryption and Hubble.
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
    # KubePrism, not a Service address: with kube-proxy disabled there is
    # nothing to implement a ClusterIP until Cilium itself is running.
    {
      name  = "k8sServiceHost"
      value = "localhost"
    },
    {
      name  = "k8sServicePort"
      value = 7445
    },
    # The chart defaults to two operator replicas with a *required* pod
    # anti-affinity on hostname, so on a cluster with fewer nodes than that
    # one replica is unschedulable forever - and helm_release waits for
    # readiness, so the apply fails rather than degrades.
    {
      name  = "operator.replicas"
      value = var.operator_replicas
    },
  ]

  lifecycle {
    ignore_changes = all
  }
}

# Hubble's trust anchor. Generated here rather than by Flux because it is a
# credential, and created up front so that it already exists when Flux turns
# Hubble on. Cilium is not configured to use it until then.
resource "tls_private_key" "hubble" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "hubble" {
  private_key_pem = tls_private_key.hubble.private_key_pem

  subject {
    common_name = "root.hubble.cluster.local"
  }

  validity_period_hours = var.hubble_ca_validity_hours

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
