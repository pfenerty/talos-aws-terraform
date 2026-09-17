# The generated files are written only when config_output_path is set. They
# carry cluster credentials, and their names are fixed, so a module that wrote
# them unconditionally into the caller's working directory would collide with
# itself the moment it was instantiated twice. The same content is available
# through this module's outputs either way.
locals {
  common_machine_config_patch = {
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
    machine = {
      kubelet = {
        extraArgs = {
          cloud-provider = "external"
        }
        registerWithFQDN = true
      }
    }
  }

  # Karpenter refuses to schedule onto a node it launched until its
  # registration controller has synced the NodeClaim's labels onto the Node,
  # and it relies on the node coming up already tainted to enforce that. For
  # the AMI families it generates user data for it injects the taint itself;
  # a Talos AMI is `amiFamily: Custom`, so the machine config has to carry it.
  # The taint is removed by Karpenter once the node is registered.
  #
  # This is spelled out as one whole patch rather than layering a second patch
  # on top of the common one: Talos merges config patches at the level of the
  # config structs, and a second patch touching machine.kubelet.extraArgs
  # could drop cloud-provider=external rather than merge with it.
  karpenter_worker_machine_config_patch = merge(local.common_machine_config_patch, {
    machine = merge(local.common_machine_config_patch.machine, {
      kubelet = merge(local.common_machine_config_patch.machine.kubelet, {
        extraArgs = merge(local.common_machine_config_patch.machine.kubelet.extraArgs, {
          "register-with-taints" = "karpenter.sh/unregistered:NoExecute"
        })
      })
    })
  })
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
  config_patches = [
    yamlencode(local.common_machine_config_patch)
  ]
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
  config_patches = [
    yamlencode(local.common_machine_config_patch)
  ]
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
  config_patches = [
    yamlencode(local.karpenter_worker_machine_config_patch)
  ]
}

resource "local_sensitive_file" "machineconfig_karpenter_worker" {
  count = var.config_output_path != null ? 1 : 0

  content  = data.talos_machine_configuration.machineconfig_karpenter_worker.machine_configuration
  filename = "${var.config_output_path}/karpenter-worker.yaml"
}
