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
      # apiServer = {
      #   admissionControl = [
      #     {
      #       name = "PodSecurity"
      #       configuration = {
      #         apiVersion = "pod-security.admission.config.k8s.io/v1alpha1"
      #         defaults = {
      #           audit           = "restricted"
      #           audit-version   = "latest"
      #           enforce         = "baseline"
      #           enforce-version = "latest"
      #           warn            = "restricted"
      #           warn-version    = "latest"
      #         }
      #         exemptions = {
      #           namespaces = [
      #             "linkerd"
      #           ]
      #           runtimeClasses = []
      #           usernames      = []
      #           kind           = "PodSecurityConfiguration"
      #         }
      #       }
      #     }
      #   ]
      # }
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
    yamlencode(local.common_machine_config_patch),
    yamlencode({
      "machine" : {
        "nodeLabels" : {
          "node.kubernetes.io/instance-type" : var.aws_topology.cp_instance_type,
          "topology.kubernetes.io/zone" : var.aws_topology.az,
          "topology.kubernetes.io/region" : var.aws_topology.region
        }
      }
    })
  ]
}

resource "local_file" "machineconfig_cp" {
  content  = talos_machine_configuration_controlplane.machineconfig_cp.machine_config
  filename = "control-plane.yaml"
}

resource "talos_machine_configuration_apply" "apply_control_plane_configs" {
  talos_config          = talos_client_configuration.talosconfig.talos_config
  machine_configuration = talos_machine_configuration_controlplane.machineconfig_cp.machine_config

  count    = length(var.control_plane_nodes)
  endpoint = var.control_plane_nodes[count.index].public_ip
  node     = var.control_plane_nodes[count.index].private_ip
}

resource "talos_machine_configuration_worker" "machineconfig_worker" {
  cluster_name       = talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = var.endpoint
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs_enabled       = false
  examples_enabled   = false
  config_patches = [
    yamlencode(local.common_machine_config_patch),
    yamlencode({
      "machine" : {
        "nodeLabels" : {
          "node.kubernetes.io/instance-type" : var.aws_topology.wk_instance_type,
          "topology.kubernetes.io/zone" : var.aws_topology.az,
          "topology.kubernetes.io/region" : var.aws_topology.region
        }
      }
    })
  ]
}

resource "local_file" "machineconfig_worker" {
  content  = talos_machine_configuration_worker.machineconfig_worker.machine_config
  filename = "worker.yaml"
}

resource "talos_machine_configuration_apply" "apply_worker_configs" {
  talos_config          = talos_client_configuration.talosconfig.talos_config
  machine_configuration = talos_machine_configuration_worker.machineconfig_worker.machine_config

  count    = length(var.worker_nodes)
  endpoint = var.worker_nodes[count.index].public_ip
  node     = var.worker_nodes[count.index].private_ip
}

resource "talos_machine_bootstrap" "talos_bootstrap" {
  talos_config = talos_client_configuration.talosconfig.talos_config
  endpoint     = var.control_plane_nodes[0].public_ip
  node         = var.control_plane_nodes[0].private_ip
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  talos_config = talos_client_configuration.talosconfig.talos_config
  endpoint     = var.control_plane_nodes[0].public_ip
  node         = var.control_plane_nodes[0].private_ip
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kube_config
  filename = "kubeconfig"
}