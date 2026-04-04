resource "helm_release" "aws_cloud_controller_manager" {
  name       = "aws-cloud-controller-manager"
  repository = "https://kubernetes.github.io/cloud-provider-aws"
  chart      = "aws-cloud-controller-manager"
  namespace  = "kube-system"

  values = [
    yamlencode({
      args = [
        "--v=2",
        "--cloud-provider=aws",
        "--cluster-name=${var.project_name}",
        "--configure-cloud-routes=false",
      ]
      nodeSelector = {
        "node-role.kubernetes.io/control-plane" = ""
      }
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
        {
          key      = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
      hostNetworking = true
    })
  ]
}
