# The AWS cloud controller manager's identity and its cloud configuration.
#
# Both halves exist because the controller no longer reads the instance
# metadata service. It used to get two things from it - credentials from the
# node's instance profile, and the region, VPC and instance identity of the
# node it happened to be running on - and the node's launch template now sets
# an IMDS hop limit of 1, which a pod cannot cross.
#
# So the credentials come from a role it assumes with its own service account
# token, and the facts come from a cloud config file. Upstream calls that
# second path "master is running on a different AWS account, different cloud
# provider or on-premise": given VPC, SubnetID and KubernetesClusterID, the
# controller builds a synthetic self-instance and never calls metadata.
# KubernetesClusterID is not optional on that path - without it the controller
# tries to describe the synthetic instance and fails at startup.

module "role" {
  source = "../irsa-role"

  name            = "${var.project_name}-cloud-controller-manager"
  service_account = "cloud-controller-manager"
  policy          = file("${path.module}/policy.json")
  oidc            = var.oidc
  tags            = var.tags
}

resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = "cloud-controller-manager-aws-config"
    namespace = "kube-system"
  }

  data = {
    # Mounted at /etc/aws/cloud.conf and named by --cloud-config. SubnetID is
    # only used to build the synthetic self-instance; load balancers still
    # pick their subnets by tag, across every subnet in the VPC.
    "cloud.conf" = <<-EOT
      [Global]
      Region = ${var.region}
      VPC = ${var.vpc_id}
      SubnetID = ${var.subnet_id}
      KubernetesClusterID = ${var.project_name}
    EOT

    # A shared AWS config file, named by AWS_CONFIG_FILE. The SDK reads
    # role_arn and web_identity_token_file from it and does the
    # AssumeRoleWithWebIdentity exchange itself.
    #
    # A file rather than the AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE
    # environment variables the other two components use, because this chart
    # has no envFrom and its env list is a Helm value - which would mean
    # putting this cluster's role ARN in the Flux repository, where nothing
    # cluster-specific belongs.
    "config" = <<-EOT
      [default]
      region = ${var.region}
      role_arn = ${module.role.role_arn}
      web_identity_token_file = ${var.token_path}
    EOT
  }
}
