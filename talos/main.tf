locals {
  common_machine_config_patch = {
    cluster = {
      network = {
        cni = {
          name = var.cni == "flannel" ? "flannel" : "none"
        }
      }
      proxy = {
        disabled = var.cni == "cilium" && var.disable_kube_proxy
      }
    }
  }
  cilium_manifests = templatefile(
    "${path.module}/cilium.patch.tfpl", 
    {cilium_manifests=indent(8, data.helm_template.cilium.manifest)}
  )
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = var.talos_version
}

resource "talos_client_configuration" "talosconfig" {
  cluster_name    = var.project_name
  machine_secrets = talos_machine_secrets.machine_secrets.machine_secrets
  endpoints       = ["https://${var.load_balancer_dns}:443"]
}

resource "local_file" "talosconfig" {
  content  = talos_client_configuration.talosconfig.talos_config
  filename = "talosconfig"
}

resource "talos_machine_configuration_controlplane" "machineconfig_cp" {
  cluster_name       = talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = "https://${var.load_balancer_dns}:443"
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs_enabled       = false
  examples_enabled   = false
  config_patches = [
    yamlencode(local.common_machine_config_patch),
    # yamlencode({
    #   "machine" : {
    #     "nodeLabels" : {
    #       "node.kubernetes.io/instance-type" : var.aws_topology.cp_instance_type,
    #       "topology.kubernetes.io/zone" : var.aws_topology.az,
    #       "topology.kubernetes.io/region" : var.aws_topology.region
    #     }
    #   }
    # })
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

  config_patches = var.cni == "cilium" ? [local.cilium_manifests] : []
}

resource "talos_machine_configuration_worker" "machineconfig_worker" {
  cluster_name       = talos_client_configuration.talosconfig.cluster_name
  cluster_endpoint   = "https://${var.load_balancer_dns}:443"
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  docs_enabled       = false
  examples_enabled   = false
  config_patches = [
    yamlencode(local.common_machine_config_patch),
    # yamlencode({
    #   "machine" : {
    #     "nodeLabels" : {
    #       "node.kubernetes.io/instance-type" : var.aws_topology.wk_instance_type,
    #       "topology.kubernetes.io/zone" : var.aws_topology.az,
    #       "topology.kubernetes.io/region" : var.aws_topology.region
    #     }
    #   }
    # })
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

  depends_on = [ 
    talos_machine_configuration_apply.apply_control_plane_configs
  ]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  talos_config = talos_client_configuration.talosconfig.talos_config
  endpoint     = var.control_plane_nodes[0].public_ip
  node         = var.control_plane_nodes[0].private_ip

  depends_on = [ 
    talos_machine_bootstrap.talos_bootstrap
  ]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kube_config
  filename = "kubeconfig"
}