# Approves the kubelets' serving certificate requests. Installed only when
# hardening.kubelet_serving_certificates is on: that setting makes each kubelet
# ask the cluster CA for a serving certificate instead of self-signing one, and
# kube-controller-manager will not approve those requests itself. It cannot
# tell whether the names a node asks for really are that node's, so something
# has to make the judgement. Without it the requests sit pending, and
# `kubectl logs`, `exec`, `port-forward` and metrics-server stop working.
#
# It is installed here rather than left to Flux so that turning the setting on
# can never leave a cluster in that state, and so the setting works with Flux
# disabled.
#
# It is needed to reach a healthy cluster, which is easy to miss. Nodes register
# and run pods with a pending serving request, but with serverTLSBootstrap on a
# kubelet has no certificate to serve with until one is approved, and Talos
# reads the control plane's static pod status from the kubelet's own API on
# port 10250. Until the request is approved Talos sees no static pods, and
# talos_cluster_health reports them missing. So the health check waits for this
# module.
#
# The ownership model is Cilium's. `ignore_changes = all` means Terraform
# creates this release and never touches it again, and Flux can adopt it with a
# HelmRelease of the same name in the same namespace. Bumping the chart version
# changes what a *new* cluster installs and does nothing to an existing one.
#
# Name resolution is the check most likely to fail, and it depends on the VPC:
# the approver looks the node's name up and requires it to resolve to the
# requesting address, and the Amazon DNS server only resolves instances' private
# names with enableDnsHostnames on. The networking module sets it.
#
# What the approver checks, in the chart's own words, is that the request comes
# from a node (`system:node:` username matching the common name), carries at
# most one DNS name, that name matches provider_regex and is prefixed by the
# node's own name, and that every IP in the request is one the name resolves
# to. provider_regex is therefore the line between a node and anything else
# that can create a CertificateSigningRequest, and is kept as narrow as the
# names this module produces.
locals {
  # The private DNS name EC2 gives an instance, which is what nodes register
  # under because the machine config sets registerWithFQDN. us-east-1 is the
  # one region that does not follow the regional pattern.
  dns_domain = var.region == "us-east-1" ? "ec2.internal" : "${var.region}.compute.internal"

  provider_regex = "^ip-\\d+-\\d+-\\d+-\\d+\\.${replace(local.dns_domain, ".", "\\.")}$"
}

resource "helm_release" "kubelet_csr_approver" {
  name       = "kube-system-kubelet-csr-approver"
  repository = "https://postfinance.github.io/kubelet-csr-approver"
  namespace  = "kube-system"
  chart      = "kubelet-csr-approver"
  version    = var.chart_version

  values = [yamlencode({
    providerRegex = local.provider_regex

    # Requests may only carry addresses from inside the VPC. A node in this
    # cluster can have no other.
    providerIpPrefixes = [var.vpc_cidr]

    replicas = var.replicas

    # The chart default tolerates the control plane taint only. Nodes also
    # carry node.cloudprovider.kubernetes.io/uninitialized until the cloud
    # controller manager initialises them, and the cloud controller manager is
    # installed by Flux, so an approver that did not tolerate it would be
    # Pending and helm_release would wait on it until it timed out.
    tolerations = [
      {
        key      = "node-role.kubernetes.io/control-plane"
        operator = "Exists"
        effect   = "NoSchedule"
      },
      {
        key      = "node.cloudprovider.kubernetes.io/uninitialized"
        operator = "Exists"
        effect   = "NoSchedule"
      },
    ]
  })]

  lifecycle {
    ignore_changes = all
  }
}
