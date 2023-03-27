locals {
  common_machine_config_patch = {
    cluster = {
      allowSchedulingOnControlPlanes = true
      network = {
        cni = {
          name = var.cni == "flannel" ? "flannel" : "none"
        }
      }
      proxy = {
        disabled = var.disable_kube_proxy
      }
      apiServer = {
        disablePodSecurityPolicy = true
      }
    }
  }
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = var.talos_version
}

resource "talos_client_configuration" "talosconfig" {
  cluster_name    = var.project_name
  machine_secrets = talos_machine_secrets.machine_secrets.machine_secrets
  endpoints       = [var.endpoint]
}

resource "local_file" "talosconfig" {
  content  = talos_client_configuration.talosconfig.talos_config
  filename = "talosconfig"
}

resource "talos_machine_configuration_controlplane" "machineconfig_cp" {
  cluster_name       = talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = var.endpoint
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs_enabled       = false
  examples_enabled   = false
  config_patches = [
    yamlencode(local.common_machine_config_patch)
  ]
}

resource "local_file" "machineconfig_cp" {
  content  = talos_machine_configuration_controlplane.machineconfig_cp.machine_config
  filename = "control-plane.yaml"
}

resource "talos_machine_configuration_worker" "machineconfig_worker" {
  cluster_name       = talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = var.endpoint
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs_enabled       = false
  examples_enabled   = false
  config_patches = [
    yamlencode(local.common_machine_config_patch)
  ]
}

resource "local_file" "machineconfig_worker" {
  content  = talos_machine_configuration_worker.machineconfig_worker.machine_config
  filename = "worker.yaml"
}