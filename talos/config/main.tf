locals {
  common_machine_config_patch = {
    cluster = {
      network = {
        cni = {
          name = "none"
        }
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
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.project_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = ["https://${var.load_balancer_dns}:443"]
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.talosconfig.talos_config
  filename = "talosconfig"
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

resource "local_file" "machineconfig_cp" {
  content  = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  filename = "control-plane.yaml"
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

resource "local_file" "machineconfig_worker" {
  content  = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  filename = "worker.yaml"
}
