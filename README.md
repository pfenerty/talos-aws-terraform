# Talos Linux AWS Kubernetes Terraform

Terraform code for creating a Kubernetes cluster in AWS using [Talos Linux](https://talos.dev)

<details>
<summary>References</summary>

[Talos AWS Terraform Example](https://github.com/siderolabs/contrib/tree/main/examples/terraform/aws)

</details>

## Modules

* Cloud Infra - Creates the cloud infastructure required for the cluster
    * VPC, Loadbalancer, security groups, autoscaling groups

* Talos
    * Config - Creates machine configs (applied as user data to the autoscaling group launch configs)
    * Bootstrap - Bootstraps Talos and creates kubeconfig

* Post Install
    * Bootstrap FluxCD (optional - disabled by default, configurable by the `post_install` terraform variable)
        * Designed to work with the [Flux Bootstrap Repository](https://github.com/pfenerty/flux-bootstrap)
        * Creates service account for AWS EBS CSI Driver and store credentials in a secret
        * Creates the AWS resources Karpenter needs and a config secret for it
    * Installs Cilium and creates keys for hubble to use cert-manager

### Service mesh

Cilium is the only mesh in the cluster. It is not optional here: Talos is
configured with `cni: none` and kube-proxy disabled, so Cilium is what makes the
cluster work at all, and running Linkerd on top of it meant two data planes
doing the same job. Pod-to-pod traffic is encrypted by Cilium's WireGuard
transparent encryption in strict mode (`pod_cidr` is the strict-mode egress
CIDR), and Hubble covers the observability side.

### Node autoscaling

Worker capacity comes from [Karpenter](https://karpenter.sh), enabled with the
`post_install.extras.karpenter` variable. The worker autoscaling group is no
longer scaled by anything: it is a fixed baseline sized by `worker_nodes_min`,
there to run Karpenter itself and the other cluster add-ons, and Karpenter
provisions everything above it.

Terraform owns the AWS side and the handoff to Flux:

* An IAM user scoped to the Karpenter controller policy, adapted from the
  upstream CloudFormation template. The EKS-only grants are dropped, along with
  the instance-profile write grants: Karpenter launches nodes into the existing
  worker instance profile rather than managing one of its own.
* An SQS interruption queue, and the EventBridge rules that feed spot
  interruption, rebalance, instance state change, capacity reservation
  interruption and health events into it.
* `karpenter.sh/discovery = <project name>` tags on the subnets and on the
  internal security group, which is how the `EC2NodeClass` selects them.
* A `karpenter-config` secret in `flux-system`.

The Karpenter `HelmRelease`, `EC2NodeClass` and `NodePool` live in the Flux
bootstrap repository and read that secret. It carries the controller
credentials, `cluster-name`, `cluster-endpoint` (Karpenter only discovers this
by itself on EKS), `region`, `interruption-queue`, `discovery-tag`,
`node-instance-profile`, `node-ami-id` and `node-user-data`.

`node-user-data` is a Talos worker machine config, so the `EC2NodeClass` needs
`amiFamily: Custom`. Two things follow from that. Karpenter does not get to
generate the user data, so the config carries
`--register-with-taints=karpenter.sh/unregistered:NoExecute` itself - Karpenter
requires that taint on nodes it launches and removes it once the `NodeClaim` is
registered. And the value is multi-line, so it has to reach the `EC2NodeClass`
through a `HelmRelease` `valuesFrom` `targetPath`; Flux `postBuild`
substitution is a plain string replace and would break the YAML indentation.


### State

There is no backend configured, so state is a local file. It holds the cluster
CA key, the Flux deploy key and the IAM access keys for the post-install
extras, all in plaintext - so it is worth moving somewhere encrypted and
locked before this is more than a scratch cluster:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket       = "your-state-bucket"
    key          = "talos-aws-terraform/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

The bucket has to exist first, with versioning on. Migrate with
`terraform init -migrate-state`.

### Credentials

The AWS provider uses the standard credential chain, so environment variables,
SSO and instance or container roles all work without configuration. Set
`aws_profile` to pin a named profile from your shared AWS config instead.

When Terraform has completed, there will be a `kubeconfig` and `talosconfig` file in your working directory; after about a minute after completion you should have a functional cluster

See `variables.tf` for available variables and descriptions

## Development

CI runs the following on every pull request; all four are worth running locally
before pushing:

```sh
terraform fmt -check -recursive -diff
terraform init -backend=false      # no state or AWS credentials needed
terraform validate
tflint --recursive
checkov -d . --config-file .checkov.yaml --framework terraform
```

`.checkov.yaml` lists the checks that do not apply to this cluster, each with
the reason. Everything else is expected to pass, so all four checks block.

Changes that existing state cannot absorb are written up in `MIGRATION.md`.

The generated `kubeconfig`, `talosconfig` and machine config files contain
cluster secrets. They are written by `local_sensitive_file` (mode 0600) and are
listed in `.gitignore` - anything new written there needs adding to both.