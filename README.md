# Talos Linux AWS Kubernetes Terraform

A reusable Terraform module for creating a Kubernetes cluster in AWS using
[Talos Linux](https://talos.dev), bootstrapped into GitOps with Flux in a
single `terraform apply`.

<details>
<summary>References</summary>

[Talos AWS Terraform Example](https://github.com/siderolabs/contrib/tree/main/examples/terraform/aws)

</details>

## Usage

Start from [`examples/full`](examples/full). Most of that file is provider
configuration, and that is unavoidable: a module cannot configure providers
on its caller's behalf, and the `kubernetes`, `helm` and `flux` providers
have to be built from the cluster's own kubeconfig, which does not exist
until the cluster module has applied.

```hcl
module "talos_cluster" {
  source = "github.com/pfenerty/talos-aws-terraform"

  project_name = "my-cluster"
  region       = "us-east-2"

  talos_api_allowed_cidr      = "203.0.113.4/32"
  kubernetes_api_allowed_cidr = "203.0.113.4/32"

  post_install = {
    flux = {
      enabled    = true
      git_url    = "ssh://git@github.com/you/flux-bootstrap.git"
      git_branch = "main"
      ssh_key    = file("~/.ssh/flux")
    }
    extras = { ebs = true, karpenter = true }
  }
}
```

The root module is a convenience wrapper. For more than one cluster in a
single configuration, call [`modules/cluster`](modules/cluster) and
[`modules/bootstrap`](modules/bootstrap) directly: neither configures a
provider, so both work with `count` and `for_each`, while the wrapper still
needs one set of `kubernetes`/`helm`/`flux` provider configurations per
cluster and Terraform cannot generate those dynamically.

## Layout

| Module | What it does |
|--------|--------------|
| [`modules/cluster`](modules/cluster) | VPC, load balancer, security groups, autoscaling groups, Talos machine configuration and bootstrap. Needs `aws`, `talos` and `local`, all configurable up front. Produces a cluster whose API server answers and whose nodes are still `NotReady`. |
| [`modules/bootstrap`](modules/bootstrap) | Cilium, the health gate, Flux, and the AWS resources the Flux repository consumes. Needs `kubernetes`, `helm` and `flux`, which can only be configured from the cluster module's outputs. |

The split is not stylistic. It is where the provider dependency actually
falls, and keeping it explicit is what lets the cluster half be reused.

## Bootstrap order

Talos runs with `cni: none` and kube-proxy disabled, so a freshly
bootstrapped cluster has no pod networking at all: CoreDNS cannot start and
every node is `NotReady`.

```
talos bootstrap → Cilium → talos_cluster_health → Flux → extras
```

Cilium is the only thing that can be installed into that cluster. Its agent,
envoy and operator workloads all run on the host network, the DaemonSets
tolerate every taint, and the operator tolerates `node.kubernetes.io/not-ready`
and `node.cloudprovider.kubernetes.io/uninitialized` specifically. The agents
reach the API server through KubePrism on `localhost:7445`, so they need
neither kube-proxy nor DNS.

Flux cannot: its controllers are ordinary pod-network Deployments and
source-controller needs CoreDNS to resolve the git remote. Which is why the
health gate sits between them rather than in front of both.

### Cilium ownership

Terraform installs a *bootstrap* Cilium - enough to get nodes to Ready,
without WireGuard encryption or Hubble - and then stops. The release carries
`lifecycle { ignore_changes = all }`, and the Cilium `HelmRelease` in the
Flux bootstrap repository adopts it and applies the full configuration,
including strict-mode WireGuard over `pod_cidr` and Hubble.

So `cilium_bootstrap_version` only affects clusters being created. On a
running cluster Cilium belongs to Flux, and upgrading it there is the
supported path. Pod traffic is unencrypted for the window between the
bootstrap install and Flux's first reconcile.

## Machine config size

The machine config is applied as EC2 user data, which AWS caps at 16 KB of
raw, pre-base64 bytes. The rendered control plane config is 11336 bytes
before hardening and 12463 with it, against a worker's 2958; additions to the
config patches spend what is left.

Each `talos_machine_configuration` data source asserts the result fits, so
this fails at plan with an error that says so. Exceeding it otherwise fails
the apply with an AWS error that does not mention user data, and Karpenter
nodes would fail to launch rather than fail a plan at all.

There is no way around the limit on this platform: the AWS platform reads
user data as-is, with no decompression, and the `talos.config` URL mechanism
is `metal`-only. This is also why Cilium is a Helm release rather than a Talos
inline manifest: rendered with the values above it is about 68 KB, and 18 KB
gzipped.

## Hardening

`hardening` turns on Pod Security Admission at `restricted` and an API server
audit policy worth reading. It is off by default because both can stop
workloads being admitted.

Most of what a Kubernetes benchmark asks for is already how Talos generates
and runs the cluster, so the variable is deliberately small - and it is the
machine config half of a baseline, not a baseline. [docs/hardening.md](docs/hardening.md)
sets out what Talos already covers, what has to be enforced in the Flux
repository or the AWS layer instead, how the config patches compose, and a
known limitation that has no good answer yet: a machine config change does
not reconfigure running nodes, it replaces them.

`hardening.kubelet_serving_certificates` is separate and opt-in. It makes the
kubelet bootstrap a CA-signed serving certificate instead of self-signing one,
and the API server verify it - but it needs a kubelet-serving CSR approver
running in the cluster, which is a Flux dependency this module cannot install.
Enable it without one and nodes still register and run pods, while `kubectl
logs`, `exec`, `port-forward` and metrics-server stop working until the CSRs
are approved. Install the approver first.

The doc also carries a rule-by-rule coverage matrix for all 92 rules of the
DISA Kubernetes STIG, marking each as covered here, owed by the Flux bootstrap
repository, uncheckable as written on an immutable node, or not covered - and
a written disposition for the 22 uncheckable ones, aimed at an assessor.

## Node autoscaling

Worker capacity comes from [Karpenter](https://karpenter.sh), enabled with
`post_install.extras.karpenter`. The worker autoscaling group is not scaled
by anything: it is a fixed baseline sized by `worker_nodes_min`, there to run
Karpenter itself and the other cluster add-ons, and Karpenter provisions
everything above it.

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
* A `karpenter-config` secret in `flux-system`, and a `karpenter-aws-credentials`
  secret in `kube-system`.

The Karpenter `HelmRelease`, `EC2NodeClass` and `NodePool` live in the Flux
bootstrap repository and read those secrets. `karpenter-config` carries
`cluster-name`, `cluster-endpoint` (Karpenter only discovers this by itself on
EKS), `region`, `interruption-queue`, `discovery-tag`,
`node-instance-profile`, `node-ami-id` and `node-user-data`, and the
`HelmRelease` reads it through `valuesFrom`, which resolves secrets in the
`HelmRelease`'s own namespace.

The credentials are in a second secret because they are not chart values: the
controller reads them from its environment, and the chart's only hook for that
is `controller.envFrom`, which resolves the secret in the *pod's* namespace.
Hence the same key pair in `kube-system`, shaped as `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_REGION`.

`node-user-data` is a Talos worker machine config, so the `EC2NodeClass` needs
`amiFamily: Custom`. Two things follow from that. Karpenter does not get to
generate the user data, so the config carries
`--register-with-taints=karpenter.sh/unregistered:NoExecute` itself - Karpenter
requires that taint on nodes it launches and removes it once the `NodeClaim` is
registered. And the value is multi-line, so it has to reach the `EC2NodeClass`
through a `HelmRelease` `valuesFrom` `targetPath`; Flux `postBuild`
substitution is a plain string replace and would break the YAML indentation.

## Flux bootstrap repository

The post-install extras are written against
[pfenerty/flux-bootstrap](https://github.com/pfenerty/flux-bootstrap) and
publish the secrets it reads - `cilium-config`, `karpenter-config`,
`karpenter-aws-credentials`, `aws-secret` and `aws-loadbalancer-config`. Using
them with a different GitOps repository means matching those names and shapes;
[`modules/bootstrap`](modules/bootstrap) documents each one.

Flux syncs `clusters/<project_name>`, and bootstrap writes only the
`flux-system` directory inside it. Everything else the cluster runs is
committed to that directory in the bootstrap repository *before* the apply:

```sh
git clone ssh://git@github.com/you/flux-bootstrap.git
cd flux-bootstrap
cp -r clusters/template clusters/my-cluster
git add clusters/my-cluster && git commit -m "Add my-cluster" && git push
```

Apply with the path empty and the cluster comes up with Flux installed and
nothing else, which is a valid thing to want but rarely what was meant. The
path is `terraform output flux_path`.

## Exposure

`talos_api_allowed_cidr` and `kubernetes_api_allowed_cidr` both default to
`0.0.0.0/0`. That is what lets `terraform apply` bootstrap the cluster from
wherever you happen to be running it, and it means both APIs are reachable from
the internet on a default apply.

The Talos API is the one to care about: port 50000 administers the machines
themselves, below Kubernetes. Set both to your own address:

```hcl
talos_api_allowed_cidr      = "203.0.113.4/32"
kubernetes_api_allowed_cidr = "203.0.113.4/32"
```

## Credentials

`kubeconfig` and `talosconfig` are outputs, both marked sensitive:

```sh
terraform output -raw kubeconfig > ~/.kube/talos
```

Nothing is written to disk unless `config_output_path` is set, which is what
a module gets to do rather than dropping fixed filenames into whatever
directory it was called from. Set it and the kubeconfig, talosconfig and
machine configs are written there at mode 0600; their names are in
`.gitignore`.

The cluster is functional when the apply returns: it blocks on
`talos_cluster_health` until etcd has quorum, every node's kubelet is up and
the control plane components are live, so there is nothing to wait out
afterwards. `cluster_health_timeout` (default 10 minutes) caps that wait. It
is a ceiling rather than a delay, but note that Terraform re-reads the health
check on refresh, so it also bounds how long a `plan` blocks when the cluster
is unreachable.

## State

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

## Development

```sh
terraform fmt -check -recursive -diff
terraform init -backend=false      # no state or AWS credentials needed
terraform validate
tflint --recursive
checkov -d . --config-file .checkov.yaml --framework terraform
```

`pre-commit install` runs all of these on commit, plus the `terraform-docs`
regeneration. `.checkov.yaml` lists the checks that do not apply to this
cluster, each with the reason.

Each module has a README with a generated variable and output table. See
`CONTRIBUTING.md` for the conventions.

## License

MIT.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| aws | ~> 6.65 |
| flux | ~> 1.9 |
| helm | ~> 3.3 |
| kubernetes | ~> 3.2 |
| local | ~> 2.9 |
| talos | ~> 0.11 |
| tls | ~> 4.4 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| bootstrap | ./modules/bootstrap | n/a |
| cluster | ./modules/cluster | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| additional\_tags | Extra tags applied to every resource this module creates, on top of the cluster, ManagedBy and Project tags. | `map(string)` | `{}` | no |
| availability\_zones | Availability Zones to create subnets in. Null means every zone the region currently reports, which is convenient but means the subnet layout changes if AWS adds a zone; pin it for anything long-lived. The availability\_zones output reports what was used. | `list(string)` | `null` | no |
| cilium\_bootstrap\_version | Cilium chart version installed to get the cluster to Ready. Changing it affects new clusters only: on an existing cluster Cilium belongs to Flux, and the bootstrap module deliberately stops reconciling the release after creating it. | `string` | `"1.20.2"` | no |
| cluster\_health\_timeout | How long to wait for the cluster to report healthy before giving up. This is a ceiling, not a delay: the check returns as soon as the cluster is ready. Terraform re-reads the health check on refresh, so this also bounds how long a plan blocks when the cluster is unreachable. | `string` | `"10m"` | no |
| config\_output\_path | Directory to write the generated kubeconfig, talosconfig and machine config files into. Null, the default, writes nothing: the same files are available as outputs, and a module that writes into the caller's directory collides with itself when instantiated more than once. The files carry cluster credentials and are written mode 0600. | `string` | `null` | no |
| control\_plane\_node\_instance\_type | AWS EC2 instance type for control plane nodes | `string` | `"t3.medium"` | no |
| control\_plane\_nodes | Number of control plane nodes. etcd needs an odd number to hold quorum; 1 is fine for a throwaway cluster but has no redundancy, and an instance refresh will briefly take the API server away. | `number` | `1` | no |
| hardening | Machine config hardening, off by default because it changes what the cluster will admit. `enabled` turns on a real API server audit policy and Pod Security Admission enforcing the standard named below. It is the machine config half of a hardening baseline and not the whole of one: docs/hardening.md sets out what it covers, what Talos already does without it, and what has to be enforced in the Flux repository or the AWS layer instead. `kubelet_serving_certificates` makes the kubelet bootstrap a CA-signed serving certificate rather than self-signing one, and requires a CSR approver running in the cluster - a Flux dependency this module cannot install, and without which `kubectl logs` and `exec` stop working. | <pre>object({<br/>    enabled                        = optional(bool, false)<br/>    pod_security_enforce           = optional(string, "restricted")<br/>    pod_security_exempt_namespaces = optional(list(string), ["kube-system"])<br/>    kubelet_serving_certificates   = optional(bool, false)<br/>  })</pre> | `{}` | no |
| hubble\_ca\_validity\_hours | Lifetime of the self-signed Hubble trust anchor, in hours. The default of 12 is carried over from before this was configurable and is almost certainly too short for a CA that cert-manager issues from - raise it, or move the trust anchor to cert-manager entirely. | `number` | `12` | no |
| kubernetes\_api\_allowed\_cidr | CIDR allowed to reach the Kubernetes API on port 6443. Open to the internet by default; narrow it to your own address where you can. | `string` | `"0.0.0.0/0"` | no |
| kubernetes\_version | Kubernetes version | `string` | `"1.37.0"` | no |
| pod\_cidr | Pod subnet CIDR. Set on the Talos machine config and reused as Cilium's strict-mode egress CIDR so the two cannot drift apart. | `string` | `"10.244.0.0/16"` | no |
| post\_install | What to install once the cluster is up. Flux bootstraps from the git repository described here; the extras are Terraform-managed AWS resources that the Flux bootstrap repository consumes, so they require Flux. Cilium is not listed: it is not optional, because the cluster cannot reach a healthy state without a CNI. | <pre>object({<br/>    flux = object({<br/>      enabled    = bool<br/>      git_url    = string<br/>      git_branch = string<br/>      ssh_key    = string<br/>    })<br/>    extras = object({<br/>      ebs       = bool<br/>      karpenter = bool<br/>    })<br/>  })</pre> | <pre>{<br/>  "extras": {<br/>    "ebs": false,<br/>    "karpenter": false<br/>  },<br/>  "flux": {<br/>    "enabled": false,<br/>    "git_branch": "",<br/>    "git_url": "",<br/>    "ssh_key": ""<br/>  }<br/>}</pre> | no |
| project\_name | Project name. Used as the prefix for every AWS resource name, as the Talos cluster name, and verbatim as the load balancer and target group name - which is what the constraints below come from. Required: every name this module creates derives from it, and several of them are account-global. | `string` | n/a | yes |
| region | AWS region the cluster runs in. This selects the Talos AMI and is handed to Karpenter; it does not configure the AWS provider, which is the caller's to set. | `string` | n/a | yes |
| talos\_api\_allowed\_cidr | CIDR allowed to reach the Talos API on port 50000. The default is open to the internet, which is what makes `terraform apply` work from anywhere but is the wrong setting for anything you care about: the Talos API administers the machines themselves. Narrow it to your own address. | `string` | `"0.0.0.0/0"` | no |
| talos\_version | Talos Linux version | `string` | `"v1.14.1"` | no |
| vpc\_cidr | IPv4 CIDR block for the VPC. Subnets are carved out of it with a /8 offset per Availability Zone, so it needs to be large enough for one /24 per zone. | `string` | `"172.31.0.0/16"` | no |
| worker\_node\_instance\_type | AWS EC2 instance type for worker nodes | `string` | `"t3.medium"` | no |
| worker\_nodes\_max | Ceiling on the worker autoscaling group. Only reached by scaling the group by hand; elastic capacity comes from Karpenter instead. Must leave at least one instance of headroom above worker\_nodes\_min, which is what a rolling instance refresh launches its replacement into. | `number` | `5` | no |
| worker\_nodes\_min | Size the worker autoscaling group is created at. Nothing scales this group: it is the static baseline that Karpenter itself and the rest of the cluster add-ons run on, and Karpenter provisions everything above it. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| availability\_zones | Availability Zones the subnets were created in. Pin var.availability\_zones to this list to stop the layout moving. |
| cluster\_endpoint | Kubernetes API endpoint, and the Talos cluster endpoint. |
| control\_plane\_autoscaling\_group\_name | Name of the control plane autoscaling group. |
| flux\_path | Path inside the Flux bootstrap repository this cluster syncs from. |
| kubeconfig | Admin kubeconfig for the cluster. Contains cluster credentials: `terraform output -raw kubeconfig > ~/.kube/talos` rather than letting it into a log. |
| load\_balancer\_dns | DNS name of the network load balancer in front of the control plane. |
| subnet\_ids | Subnets the cluster runs in, ordered by Availability Zone. |
| talos\_ami\_id | AMI the cluster nodes boot from. |
| talosconfig | Talos client configuration. Contains cluster credentials. |
| vpc\_id | ID of the VPC the cluster runs in. |
<!-- END_TF_DOCS -->
