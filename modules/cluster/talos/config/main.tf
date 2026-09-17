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
#   2. Lists append. Three fields in the whole of v1alpha1 are tagged
#      merge:"replace" - cluster.network.podSubnets, cluster.network.serviceSubnets
#      and cluster.apiServer.auditPolicy. Every other list-valued field appends
#      to whatever is already there, and `talosctl gen config` populates several
#      of them, so patching one naively duplicates its contents rather than
#      replacing them.
#   3. To replace a list the generator already populated, delete it in one patch
#      and set it in the next: a single patch may not modify the same document
#      twice, so this needs two. See local.hardening_reset_patch.
#   4. A patch may add configuration documents the generated config does not
#      have, matched on apiVersion/kind/name - but only documents the provider's
#      vendored machinery knows. See the version-skew note below.
#
# Version skew, deliberate: Talos 1.14 moves nearly all of the settings below
# into dedicated configuration documents (KubeAPIServerConfig, KubeletConfig,
# KubeAuditPolicyConfig, KubeAdmissionControlConfig, SysctlConfig, ...) and
# deprecates the v1alpha1 fields they replace. Those documents are not reachable
# from here yet: terraform-provider-talos 0.11.0 vendors Talos machinery 1.13,
# which is what generates this configuration and applies these patches, and it
# rejects document kinds it does not know - regardless of what var.talos_version
# says the nodes will run. The deprecated fields still work in 1.14. Revisit
# when the provider bumps its machinery; docs/hardening.md carries the mapping.
locals {
  # EC2 caps user data at 16 KB of raw, pre-base64 bytes, and on this platform
  # the machine config is the user data. Enforced by the postconditions below
  # rather than left to AWS, whose error for exceeding it does not mention the
  # limit. See "Machine config size" in the README.
  user_data_limit_bytes = 16384

  # Applies to every machine whatever its role.
  cluster_patch = {
    cluster = {
      network = {
        cni = {
          name = "none"
        }
        podSubnets = [var.pod_cidr]
      }
      proxy = {
        disabled = true
      }
      externalCloudProvider = {
        enabled = true
      }
    }
    machine = {
      kubelet = {
        extraArgs = {
          cloud-provider = "external"
        }
        registerWithFQDN = true
      }
    }
  }

  # kube-apiserver and kube-controller-manager only ever run on a control plane
  # node, so this is not in cluster_patch: on a worker it would be inert
  # configuration spending user data that worker has a fixed 16 KB of.
  control_plane_patch = {
    cluster = {
      apiServer = {
        extraArgs = {
          cloud-provider = "external"
        }
      }
      controllerManager = {
        extraArgs = {
          cloud-provider = "external"
        }
      }
    }
  }

  # Karpenter refuses to schedule onto a node it launched until its
  # registration controller has synced the NodeClaim's labels onto the Node,
  # and it relies on the node coming up already tainted to enforce that. For
  # the AMI families it generates user data for it injects the taint itself;
  # a Talos AMI is `amiFamily: Custom`, so the machine config has to carry it.
  # The taint is removed by Karpenter once the node is registered.
  karpenter_taint_patch = {
    machine = {
      kubelet = {
        extraArgs = {
          "register-with-taints" = "karpenter.sh/unregistered:NoExecute"
        }
      }
    }
  }

  # `talosctl gen config` writes a PodSecurity entry into
  # cluster.apiServer.admissionControl, and that field is a list, so rule 2
  # above applies: setting it directly would leave the config carrying two
  # PodSecurity plugin configurations. This patch clears the generated one so
  # that hardening_control_plane_patch, applied immediately after it, is the
  # only one left.
  hardening_reset_patch = {
    cluster = {
      apiServer = {
        admissionControl = {
          "$patch" = "delete"
        }
      }
    }
  }

  hardening_control_plane_patch = {
    cluster = {
      apiServer = {
        admissionControl = [
          {
            name = "PodSecurity"
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
          }
        ]

        # Talos already sets audit-log-path, -maxage 30, -maxbackup 10 and
        # -maxsize 100 on kube-apiserver; what it does not set is a policy
        # worth reading, defaulting to a single `level: Metadata` catch-all.
        # This keeps that as the floor, drops the highest-volume reads, and
        # raises writes that change authorization to full bodies. Secrets stay
        # at Metadata on purpose: RequestResponse on them would copy secret
        # values into the audit log. auditPolicy is one of the three fields
        # that replaces rather than appends, so this needs no reset patch.
        auditPolicy = {
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
    }
  }

  # There is deliberately no kubelet half to this. Everything a benchmark asks
  # for on the node is already how Talos generates and runs it: the generated
  # config carries defaultRuntimeSeccompProfileEnabled: true, and the kubelet
  # is started with anonymous authentication off, webhook authn/authz,
  # rotateCertificates, protectKernelDefaults and a 5m streaming idle timeout
  # whatever the config says. A patch setting any of them renders byte for byte
  # identical output, so hardening only has a control plane half.
  #
  # serverTLSBootstrap is the one real remaining delta and is left off on
  # purpose: it needs something in the cluster approving kubelet serving CSRs,
  # and without an approver the node's serving certificate never issues. See
  # docs/hardening.md.

  # Encoded here rather than where they are consumed: the patches are objects
  # of different shapes, and a conditional whose arms are lists of them has no
  # common element type to unify on. As YAML they are all just strings, which
  # is what `config_patches` takes anyway.
  #
  # Order matters: the reset has to land before the patch that repopulates the
  # list it clears.
  hardening_control_plane_patches = var.hardening.enabled ? [
    yamlencode(local.hardening_reset_patch),
    yamlencode(local.hardening_control_plane_patch),
  ] : []

  control_plane_patches = concat(
    [yamlencode(local.cluster_patch), yamlencode(local.control_plane_patch)],
    local.hardening_control_plane_patches,
  )

  worker_patches = [yamlencode(local.cluster_patch)]

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
