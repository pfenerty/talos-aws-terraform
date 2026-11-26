# The generated files are written only when config_output_path is set. They
# carry cluster credentials, and their names are fixed, so a module that wrote
# them unconditionally into the caller's working directory would collide with
# itself the moment it was instantiated twice. The same content is available
# through this module's outputs either way.

# Config patches compose. HCL merge() does not, and does not need to.
#
# Talos applies each element of `config_patches` in order, as a strategic merge
# against the whole configuration, so one patch per concern is the supported way
# to build this up. Four rules decide what that does, and only the second is a
# surprise:
#
#   1. Maps merge key by key. Two patches that both touch
#      machine.kubelet.extraArgs produce the union of their keys, so a later
#      patch adding an argument cannot drop an earlier one. This file used to
#      merge its patches in HCL to avoid exactly that, which strategic merge
#      does not in fact do.
#   2. Lists append. Only KubeNetworkConfig.podSubnets and .serviceSubnets are
#      overwritten on merge, and KubeAuditPolicyConfig.configuration is replaced
#      whole. Every other list-valued field appends to whatever is already
#      there, and `talosctl gen config` populates several of them, so patching
#      one naively duplicates its contents rather than replacing them.
#   3. To replace a list the generator already populated, delete it in one patch
#      and set it in the next: a single patch may not modify the same document
#      twice, so this needs two. See local.hardening_reset_patch.
#   4. A patch may add configuration documents the generated config does not
#      have, matched on apiVersion/kind/name, and may remove a generated one
#      with `$patch: delete`.
#
# Documents, not v1alpha1 fields. Talos 1.14 moved nearly everything below out
# of v1alpha1 into dedicated documents (UnattendedInstallConfig, KubeletConfig,
# KubeNodeConfig, KubeNetworkConfig, KubeProxyConfig, KubeAPIServerConfig, ...)
# and refuses a configuration that sets the same thing in both places. Which of
# the two the generator writes depends on the machinery vendored by
# terraform-provider-talos: 0.12 vendors Talos 1.14 and, given a 1.14
# talos_version, writes the documents. A v1alpha1 patch for one of those settings
# is then a conflict, and it is not caught at plan or apply time - the data
# source does not validate what it renders - but by the node, at boot, when it
# acquires its config from user data and rejects it. That is why versions.tf
# requires provider 0.12 or later. Only what has no document yet is still
# patched into v1alpha1: cluster.externalCloudProvider.
#
# Every document patched here is matched by kind, so a kind the generated config
# does not carry is added rather than merged. `talosctl validate --mode cloud`
# against the rendered files is the check that catches a mistake in this file.
locals {
  # EC2 caps user data at 16 KB of raw, pre-base64 bytes, and on this platform
  # the machine config is the user data. Enforced by the postconditions below
  # rather than left to AWS, whose error for exceeding it does not mention the
  # limit. See "Machine config size" in the README.
  user_data_limit_bytes = 16384

  # Applies to every machine whatever its role. One patch, several documents:
  # each kind appears once, which is all the "one patch, one modification per
  # document" rule asks.
  cluster_patch = join("\n---\n", [
    # The only setting here that is still v1alpha1. This is what makes Talos
    # pass `--cloud-provider=external` to the kubelet, and to kube-apiserver and
    # kube-controller-manager on Kubernetes versions that still have the flag.
    # Kubernetes 1.33 removed it from those two, and Talos leaves it off there.
    # It must not be repeated in any extraArgs: kube-apiserver exits at startup
    # on `unknown flag: --cloud-provider`, which takes the whole control plane
    # with it.
    yamlencode({
      cluster = {
        externalCloudProvider = {
          enabled = true
        }
      }
    }),

    # Cilium is the CNI, installed by the bootstrap module, so the generated
    # Flannel is removed outright: the document's presence is what deploys it.
    # KubeNetworkConfig.podSubnets overwrites rather than appends, so this
    # replaces the generator's 10.244.0.0/16 and needs no reset patch.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNetworkConfig"
      podSubnets = [var.pod_cidr]
    }),


    # `talosctl gen config` writes the installer image of the machinery that
    # generated the config - a factory.talos.dev metal-installer reference at
    # the machinery's own version, 1.14.0 as of terraform-provider-talos 0.12 -
    # regardless of what var.talos_version says the nodes will run. It is inert
    # for as long as a node only ever boots from the AMI, which is why it went
    # unnoticed, and it is the wrong installer the moment anything upgrades a
    # node in place: the node would install that version over whatever it was
    # running.
    #
    # The disk selector restates what the generator wrote, because a merge that
    # does not carry it drops it and the document is then invalid (match is
    # required). It matches nothing on AWS, where the root volume is an NVMe
    # device, and that is fine: the install only runs on a node that is not yet
    # installed to disk, and every node here boots from an AMI that is.
    #
    # Shorter than the string it replaces, so it costs nothing against the
    # 16 KB user data ceiling.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = "ghcr.io/siderolabs/installer:${var.talos_version}"
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
        wipe = false
      }
    }),

    # CoreDNS forwards to the VPC's resolver directly rather than through the
    # host DNS cache. Talos's host DNS answers a node's own name with every
    # address that node has - its VPC address, its public IP and its pod-network
    # address - where the VPC resolver returns the VPC address alone. Anything
    # that checks a node's name against its address then fails on whichever node
    # CoreDNS happens to be running on: the kubelet serving certificate approver
    # refuses a request when the name resolves to an address outside the VPC,
    # which leaves that node's kubelet with no certificate and the cluster
    # unable to report healthy. Host DNS itself stays on for the nodes. The
    # cost is that CoreDNS and the host no longer share a cache.
    #
    # CoreDNS reads this when it starts: on a cluster that is already running,
    # restart it after the change lands (kubectl -n kube-system rollout restart
    # deploy/coredns).
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      hostDNS = {
        forwardKubeDNSToHost = false
      }
    }),

    # AWS node names are the instance's private DNS name, which is what the
    # cloud controller manager looks nodes up by.
    yamlencode({
      apiVersion       = "v1alpha1"
      kind             = "KubeNodeConfig"
      registerWithFQDN = true
    }),
  ])

  # kube-apiserver and kube-controller-manager only ever run on a control plane
  # node, so this is not in cluster_patch: on a worker it would be inert
  # configuration spending user data that worker has a fixed 16 KB of.
  control_plane_patch = join("\n---\n", [
    # Cilium replaces kube-proxy. The generator only writes this document for
    # control plane machines, and refuses it on a worker.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeProxyConfig"
      enabled    = false
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeAPIServerConfig"
      extraArgs = {
        # IRSA, which is how everything in the cluster that talks to AWS
        # authenticates: the cloud controller manager, the EBS CSI driver
        # and Karpenter all trade a projected service account token for
        # role credentials rather than holding a key pair.
        #
        # AWS can only verify those tokens if it can fetch the issuer's
        # discovery document and public keys, so the issuer is an S3 URL
        # rather than the in-cluster default. `jwks_uri` is not set here:
        # the API server advertises its own node address for it, not one
        # derived from the issuer, so the bootstrap module rewrites it to the
        # bucket when it copies the discovery document out (modules/bootstrap/
        # oidc), at exactly the path it publishes the keys to.
        #
        # Talos prepends a service-account-issuer given here to the one it
        # derives from the cluster endpoint, so the S3 URL is what new tokens
        # are signed with and the endpoint URL stays an accepted issuer.
        #
        # api-audiences keeps the issuer as an accepted audience, which is
        # what it defaults to when unset, so ordinary in-cluster tokens are
        # unaffected; sts.amazonaws.com is the audience AWS requires.
        service-account-issuer = var.service_account_issuer
        api-audiences          = "${var.service_account_issuer},sts.amazonaws.com"
      }
    }),
  ])

  # Karpenter refuses to schedule onto a node it launched until its
  # registration controller has synced the NodeClaim's labels onto the Node,
  # and it relies on the node coming up already tainted to enforce that. For
  # the AMI families it generates user data for it injects the taint itself;
  # a Talos AMI is `amiFamily: Custom`, so the machine config has to carry it.
  # The taint is removed by Karpenter once the node is registered.
  karpenter_taint_patch = {
    apiVersion = "v1alpha1"
    kind       = "KubeletConfig"
    extraArgs = {
      "register-with-taints" = "karpenter.sh/unregistered:NoExecute"
    }
  }

  # How anything running inside the cluster reaches the Talos API. Talos will
  # issue a client certificate to a service account in one of the namespaces
  # named here, carrying the roles named here, which is what an in-cluster
  # upgrade controller needs in order to call the upgrade API on each node.
  #
  # Off by default, and not part of `hardening`, because it is the opposite of
  # hardening: os:admin is root on the machine as far as Talos is concerned,
  # and a pod holding it can read the machine config - certificate keys and
  # all - and replace it. docs/hardening.md sets out the trade.
  #
  # The generated config does not carry a KubeTalosAPIAccessConfig at all, so
  # this adds the document and rule 2 above does not bite: there is no
  # generated list for allowedRoles to append to.
  kubernetes_talos_api_access_patch = {
    apiVersion                  = "v1alpha1"
    kind                        = "KubeTalosAPIAccessConfig"
    allowedRoles                = var.kubernetes_talos_api_access.roles
    allowedKubernetesNamespaces = var.kubernetes_talos_api_access.namespaces
  }

  # `talosctl gen config` writes a PodSecurity KubeAdmissionControlConfig, and
  # a merge appends to the lists inside its configuration rather than replacing
  # them, so setting it directly would leave kube-system in the exemptions
  # twice, and any exemption this module no longer wants still there. This
  # patch removes the generated document so that hardening_control_plane_patch,
  # applied immediately after it, is the only one left.
  hardening_reset_patch = {
    apiVersion = "v1alpha1"
    kind       = "KubeAdmissionControlConfig"
    name       = "PodSecurity"
    "$patch"   = "delete"
  }

  hardening_control_plane_patch = join("\n---\n", [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeAdmissionControlConfig"
      name       = "PodSecurity"
      configuration = {
        apiVersion = "pod-security.admission.config.k8s.io/v1alpha1"
        kind       = "PodSecurityConfiguration"
        defaults = {
          enforce         = var.hardening.pod_security_enforce
          enforce-version = "latest"
          audit           = "restricted"
          audit-version   = "latest"
          warn            = "restricted"
          warn-version    = "latest"
        }
        exemptions = {
          usernames      = []
          runtimeClasses = []
          namespaces     = var.hardening.pod_security_exempt_namespaces
        }
      }
    }),
    yamlencode(local.hardening_audit_policy_patch),
  ])

  # Talos already sets audit-log-path, -maxage 30, -maxbackup 10 and
  # -maxsize 100 on kube-apiserver; what it does not set is a policy worth
  # reading, defaulting to a single `level: Metadata` catch-all. This keeps
  # that as the floor, drops the highest-volume reads, and raises writes that
  # change authorization to full bodies. Secrets stay at Metadata on purpose:
  # RequestResponse on them would copy secret values into the audit log.
  # KubeAuditPolicyConfig.configuration replaces rather than merges, so this
  # needs no reset patch.
  hardening_audit_policy_patch = {
    apiVersion = "v1alpha1"
    kind       = "KubeAuditPolicyConfig"
    configuration = {
      apiVersion = "audit.k8s.io/v1"
      kind       = "Policy"
      omitStages = ["RequestReceived"]
      rules = [
        {
          level = "None"
          verbs = ["get", "list", "watch"]
          resources = [{
            group     = ""
            resources = ["events"]
          }]
        },
        {
          level = "Metadata"
          resources = [{
            group     = ""
            resources = ["secrets", "configmaps"]
          }]
        },
        {
          level = "RequestResponse"
          resources = [{
            group     = "rbac.authorization.k8s.io"
            resources = ["*"]
          }]
        },
        {
          level = "RequestResponse"
          verbs = ["create", "update", "patch", "delete"]
          resources = [{
            group     = ""
            resources = ["pods", "namespaces", "nodes", "serviceaccounts"]
          }]
        },
        {
          level = "Metadata"
        },
      ]
    }
  }

  # Almost everything a benchmark asks for on the node is already how Talos
  # generates and runs it: the generated config carries
  # defaultRuntimeSeccompProfileEnabled: true, and the kubelet is started with
  # anonymous authentication off, webhook authn/authz, rotateCertificates,
  # protectKernelDefaults and a 5m streaming idle timeout whatever the config
  # says. Patches setting any of them render byte for byte identical output.
  #
  # The one real exception is the kubelet's serving certificate, which is why
  # the two patches below exist and why they are behind their own variable
  # rather than hardening.enabled.
  #
  # Left alone, the kubelet self-signs its serving certificate and the API
  # server does not check it. serverTLSBootstrap makes the kubelet request one
  # from the cluster CA instead, and kubelet-certificate-authority makes the
  # API server verify what it is given - each is pointless without the other,
  # so they are set together.
  #
  # Both depend on a component that is not part of the machine config.
  # kube-controller-manager will not auto-approve kubernetes.io/kubelet-serving CSRs, by design: it
  # cannot tell whether the SANs a node asks for are really that node's. Until
  # an approver is running in the cluster the CSRs stay pending, and a kubelet
  # with no serving certificate still registers its node and still runs pods -
  # what breaks is anything the API server opens a connection *to* the kubelet
  # for, so `kubectl logs`, `exec`, `port-forward` and metrics-server. The
  # approver is installed by the bootstrap module when this is on, and named in
  # docs/hardening.md.
  hardening_kubelet_serving_patch = {
    apiVersion = "v1alpha1"
    kind       = "KubeletConfig"
    config = {
      serverTLSBootstrap = true
    }
  }

  # Merges into the extraArgs set by control_plane_patch: maps merge key by
  # key, so this adds a flag rather than replacing the IRSA ones. The path is
  # the API server static pod's own copy of the cluster CA, which Talos already
  # mounts and passes as client-ca-file.
  hardening_kubelet_serving_control_plane_patch = {
    apiVersion = "v1alpha1"
    kind       = "KubeAPIServerConfig"
    extraArgs = {
      kubelet-certificate-authority = "/system/secrets/kubernetes/kube-apiserver/ca.crt"
    }
  }

  # Encoded here rather than where they are consumed: the patches are objects
  # of different shapes, and a conditional whose arms are lists of them has no
  # common element type to unify on. As YAML they are all just strings, which
  # is what `config_patches` takes anyway.
  #
  # Order matters: the reset has to land before the patch that repopulates the
  # list it clears.
  hardening_control_plane_patches = var.hardening.enabled ? [
    yamlencode(local.hardening_reset_patch),
    local.hardening_control_plane_patch,
  ] : []

  # Applied to every role, control plane included: the control plane nodes run
  # kubelets too, and `kubectl logs` against a control plane node goes through
  # the same serving certificate.
  kubelet_serving_patches = var.hardening.kubelet_serving_certificates ? [
    yamlencode(local.hardening_kubelet_serving_patch),
  ] : []

  kubelet_serving_control_plane_patches = var.hardening.kubelet_serving_certificates ? [
    yamlencode(local.hardening_kubelet_serving_control_plane_patch),
  ] : []

  # Control plane only: Talos refuses this on a worker, both as a document and
  # as the v1alpha1 feature flag it replaces, and fails the node's config
  # validation rather than ignoring it.
  kubernetes_talos_api_access_patches = var.kubernetes_talos_api_access.enabled ? [
    yamlencode(local.kubernetes_talos_api_access_patch),
  ] : []

  control_plane_patches = concat(
    [local.cluster_patch, local.control_plane_patch],
    local.hardening_control_plane_patches,
    local.kubelet_serving_patches,
    local.kubelet_serving_control_plane_patches,
    local.kubernetes_talos_api_access_patches,
  )

  worker_patches = concat(
    [local.cluster_patch],
    local.kubelet_serving_patches,
  )

  karpenter_worker_patches = concat(
    local.worker_patches,
    [yamlencode(local.karpenter_taint_patch)],
  )
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.project_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = ["https://${var.load_balancer_dns}:443"]
}

resource "local_sensitive_file" "talosconfig" {
  count = var.config_output_path != null ? 1 : 0

  content  = data.talos_client_configuration.talosconfig.talos_config
  filename = "${var.config_output_path}/talosconfig"
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name       = data.talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = "https://${var.load_balancer_dns}:443"
  machine_type       = "controlplane"
  talos_version      = talos_machine_secrets.machine_secrets.talos_version
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches     = local.control_plane_patches

  # nonsensitive() because machine_configuration is a sensitive attribute and
  # a condition may not produce a sensitive result. Only its length crosses.
  lifecycle {
    postcondition {
      condition     = nonsensitive(length(self.machine_configuration)) <= local.user_data_limit_bytes
      error_message = "The control plane machine config is larger than the 16 KB EC2 user data limit, so the launch template would be rejected at apply time. Remove settings from the config patches, or move what does not have to be in the machine config into the Flux bootstrap repository."
    }
  }
}

resource "local_sensitive_file" "machineconfig_cp" {
  count = var.config_output_path != null ? 1 : 0

  content  = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  filename = "${var.config_output_path}/control-plane.yaml"
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name       = data.talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = "https://${var.load_balancer_dns}:443"
  machine_type       = "worker"
  talos_version      = talos_machine_secrets.machine_secrets.talos_version
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches     = local.worker_patches

  lifecycle {
    postcondition {
      condition     = nonsensitive(length(self.machine_configuration)) <= local.user_data_limit_bytes
      error_message = "The worker machine config is larger than the 16 KB EC2 user data limit, so the launch template would be rejected at apply time. Remove settings from the config patches, or move what does not have to be in the machine config into the Flux bootstrap repository."
    }
  }
}

resource "local_sensitive_file" "machineconfig_worker" {
  count = var.config_output_path != null ? 1 : 0

  content  = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  filename = "${var.config_output_path}/worker.yaml"
}

data "talos_machine_configuration" "machineconfig_karpenter_worker" {
  cluster_name       = data.talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = "https://${var.load_balancer_dns}:443"
  machine_type       = "worker"
  talos_version      = talos_machine_secrets.machine_secrets.talos_version
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches     = local.karpenter_worker_patches

  # Karpenter hands this to EC2 as user data the same way the launch templates
  # do, so it is held to the same limit.
  lifecycle {
    postcondition {
      condition     = nonsensitive(length(self.machine_configuration)) <= local.user_data_limit_bytes
      error_message = "The Karpenter worker machine config is larger than the 16 KB EC2 user data limit, so Karpenter would fail to launch nodes with it. Remove settings from the config patches, or move what does not have to be in the machine config into the Flux bootstrap repository."
    }
  }
}

resource "local_sensitive_file" "machineconfig_karpenter_worker" {
  count = var.config_output_path != null ? 1 : 0

  content  = data.talos_machine_configuration.machineconfig_karpenter_worker.machine_configuration
  filename = "${var.config_output_path}/karpenter-worker.yaml"
}
