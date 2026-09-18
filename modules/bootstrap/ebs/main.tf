# The EBS CSI driver's identity.
#
# A role the controller assumes with its own service account token, rather
# than an IAM user and a key pair in a secret. The node plugin gets nothing:
# it only mounts volumes that are already attached, and with
# `metadataSources: kubernetes` in the Flux bootstrap repository it reads the
# instance facts it needs off its own Node object instead of from instance
# metadata, which a pod can no longer reach.
module "role" {
  source = "../irsa-role"

  name            = "${var.project_name}-ebs-csi-driver"
  service_account = "ebs-csi-controller-sa"
  policy = templatefile("${path.module}/ebs-iam.json.tmpl", {
    account_id   = var.aws_account_id,
    project_name = var.project_name
  })
  oidc = var.oidc
  tags = var.tags
}

# Read by the controller through `envFrom`, which is all this chart needs:
# given a role ARN and a token file the AWS SDK does the
# AssumeRoleWithWebIdentity exchange itself.
resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = "ebs-csi-driver-aws-config"
    namespace = "kube-system"
  }

  data = {
    AWS_REGION                  = var.region
    AWS_ROLE_ARN                = module.role.role_arn
    AWS_WEB_IDENTITY_TOKEN_FILE = var.token_path
  }
}
