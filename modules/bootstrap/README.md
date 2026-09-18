# modules / bootstrap

Everything that happens against a running cluster: Cilium, the health gate,
Flux, and the AWS resources the Flux bootstrap repository consumes.

Order matters here and is the reason this module exists separately:

1. **Cilium**, which is the only thing that can be installed into a cluster
   with no CNI. Its agent, envoy and operator all run on the host network,
   the DaemonSets tolerate every taint, and the operator tolerates
   `node.kubernetes.io/not-ready` and
   `node.cloudprovider.kubernetes.io/uninitialized` specifically. The agents
   reach the API server over KubePrism on `localhost:7445`, so they need
   neither kube-proxy nor DNS.
2. **`talos_cluster_health`**, which now has something to wait for. Before
   Cilium, nodes never go Ready and this gate can only time out.
3. **Flux**, whose controllers are ordinary pod-network Deployments and
   whose source-controller needs CoreDNS to resolve the git remote. Flux
   cannot be bootstrapped before step 1.
4. **The cluster's OIDC identity provider**, which publishes the API server's
   discovery documents to S3 and registers them with IAM. Everything that
   follows authenticates to AWS by assuming a role with a service account
   token, so this has to exist before any of it starts.
5. **The extras**, which publish roles and configuration into Kubernetes for
   the bootstrap repository to consume.

## Cilium ownership

The `helm_release` here is the *bootstrap* install: enough Cilium for nodes
to reach Ready, without WireGuard encryption or Hubble. It carries
`lifecycle { ignore_changes = all }`, so Terraform creates it once and never
reconciles it again, and the Cilium `HelmRelease` in the Flux bootstrap
repository adopts the release and applies the full configuration.

Two consequences:

* Pod traffic is unencrypted between this install and Flux's first
  reconcile.
* `cilium_bootstrap_version` only affects new clusters. Upgrading Cilium on
  a running cluster is Flux's job.

## Flux bootstrap repository contract

This module is written against
[pfenerty/flux-bootstrap](https://github.com/pfenerty/flux-bootstrap) and
publishes the values that repository reads:

| Object | Namespace | Written when |
|--------|-----------|--------------|
| `cilium-config` secret | `flux-system` | Flux enabled. Carries `pod-cidr`, which the Cilium HelmRelease needs as its strict-mode egress CIDR - it must match the pod CIDR the machine configs were generated with. |
| `karpenter-config` secret | `flux-system` | `extras.karpenter`. Read by `valuesFrom`, which resolves secrets in the HelmRelease's namespace. |
| `cloud-controller-manager-aws-config` ConfigMap | `kube-system` | Flux enabled. `cloud.conf` for `--cloud-config`, and a shared AWS config file naming the role to assume. |
| `ebs-csi-driver-aws-config` ConfigMap | `kube-system` | `extras.ebs`. `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_REGION`. |
| `karpenter-aws-config` ConfigMap | `kube-system` | `extras.karpenter`. The same three variables. |
| `aws-loadbalancer-config` secret | `flux-system` | Flux enabled. Nothing in the bootstrap repository reads it today. |

None of these carries an AWS credential. Each component assumes a role with a
projected service account token, mounted at `/var/run/secrets/aws/token` -
a path that appears both in the config written here and in the volume mount
in the bootstrap repository, and that nothing checks the agreement of. A
mismatch surfaces as an `AssumeRoleWithWebIdentity` failure in the workload's
logs, not as an error here.

Flux syncs `clusters/<project_name>`, and `flux_bootstrap_git` writes only
`flux-system` inside it. The Kustomizations that describe what the cluster runs
are committed to that directory beforehand, which is why the path is the
project name rather than something generated: a path that is not known until
after the apply cannot be populated before it.

`flux.patch.yaml` patches every Flux Deployment to tolerate
`node.cloudprovider.kubernetes.io/uninitialized`. This is load-bearing: with
`cloud-provider=external` the nodes carry that taint until the AWS cloud
controller manager runs, and the cloud controller manager is installed *by*
Flux. Remove the patch and every Flux pod stays Pending forever.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |
| flux | ~> 1.9 |
| helm | ~> 3.3 |
| http | ~> 3.5 |
| kubernetes | ~> 3.2 |
| talos | ~> 0.11 |
| tls | ~> 4.4 |

## Providers

| Name | Version |
|------|---------|
| aws | 6.65.0 |
| flux | 1.9.5 |
| kubernetes | 3.2.1 |
| talos | 0.11.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| cilium | ./cilium | n/a |
| cloud\_controller | ./cloud-controller | n/a |
| ebs | ./ebs | n/a |
| karpenter | ./karpenter | n/a |
| oidc | ./oidc | n/a |

## Resources

| Name | Type |
|------|------|
| [flux_bootstrap_git.this](https://registry.terraform.io/providers/fluxcd/flux/latest/docs/resources/bootstrap_git) | resource |
| [kubernetes_secret_v1.aws_lb_config](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_secret_v1.cilium_config](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [talos_cluster_health.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/cluster_health) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cilium\_bootstrap\_version | Cilium chart version installed to get the cluster to Ready. Changing it affects new clusters only: on an existing cluster Cilium belongs to Flux, and this module deliberately stops reconciling the release after creating it. | `string` | `"1.20.2"` | no |
| cluster | Everything this module needs to know about the cluster it is bootstrapping. Pass the cluster module's bootstrap\_inputs output straight through. | <pre>object({<br/>    project_name      = string<br/>    region            = string<br/>    pod_cidr          = string<br/>    cluster_endpoint  = string<br/>    load_balancer_dns = string<br/>    client_configuration = object({<br/>      ca_certificate     = string<br/>      client_certificate = string<br/>      client_key         = string<br/>    })<br/>    control_plane_public_ips        = list(string)<br/>    control_plane_private_ips       = list(string)<br/>    worker_private_ips              = list(string)<br/>    node_count                      = number<br/>    worker_instance_profile_name    = string<br/>    worker_iam_role_arn             = string<br/>    worker_ami_id                   = string<br/>    karpenter_worker_machine_config = string<br/><br/>    # IRSA. The bucket is created here but named by the cluster module,<br/>    # because the issuer URL built from it is in the API server's machine<br/>    # config, and the cluster module is what renders that.<br/>    oidc_bucket     = string<br/>    oidc_issuer_url = string<br/><br/>    # Facts the cloud controller manager is given in its cloud config, now<br/>    # that a pod cannot read them from the instance metadata service.<br/>    vpc_id    = string<br/>    subnet_id = string<br/><br/>    # Admin credentials for the Kubernetes API, used to read the cluster's<br/>    # own OIDC discovery documents. The endpoints are not anonymous.<br/>    kubernetes_client_configuration = object({<br/>      ca_certificate     = string<br/>      client_certificate = string<br/>      client_key         = string<br/>    })<br/><br/>    tags = map(string)<br/>  })</pre> | n/a | yes |
| cluster\_health\_timeout | How long to wait for the cluster to report healthy before giving up. This is a ceiling, not a delay: the check returns as soon as the cluster is ready. Terraform re-reads the health check on refresh, so this also bounds how long a plan blocks when the cluster is unreachable. | `string` | `"10m"` | no |
| extras | Terraform-managed AWS resources that the Flux bootstrap repository consumes. They publish their credentials into flux-system secrets, so they require Flux. | <pre>object({<br/>    ebs       = bool<br/>    karpenter = bool<br/>  })</pre> | <pre>{<br/>  "ebs": false,<br/>  "karpenter": false<br/>}</pre> | no |
| flux | Flux bootstrap. Disabled by default; when enabled, Flux is bootstrapped from the git repository described here and takes ownership of everything in the cluster, Cilium's day-2 configuration included. | <pre>object({<br/>    enabled    = bool<br/>    git_url    = string<br/>    git_branch = string<br/>    ssh_key    = string<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "git_branch": "",<br/>  "git_url": "",<br/>  "ssh_key": ""<br/>}</pre> | no |
| hubble\_ca\_validity\_hours | Lifetime of the self-signed Hubble trust anchor, in hours. The default of 12 is carried over from before this was configurable and is almost certainly too short for a CA that cert-manager issues from - raise it, or move the trust anchor to cert-manager entirely. | `number` | `12` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster\_healthy | Set once the cluster has reported healthy. Depend on this to order work after the cluster is usable. |
| flux\_path | Path inside the Flux bootstrap repository this cluster syncs from. |
<!-- END_TF_DOCS -->
