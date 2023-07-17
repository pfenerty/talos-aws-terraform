# Talos Linux AWS Kubernetes Terraform

Terraform code for creating a Kubernetes cluster in AWS using [Talos Linux](https://talos.dev)

<details>
<summary>References</summary>

[Talos AWS Terraform Example](https://github.com/siderolabs/contrib/tree/main/examples/terraform/aws)

</details>

## Modules

* Cloud Infra - creates the cloud infastructure required for the cluster
    * VPC, Loadbalancer, security groups, instances

* Talos - creates machine configs, applies them to the appropriate nodes, and bootstraps the cluster
    * Cilium - by default Cilium will be used as the CNI with hubble enabled

* Post Install (optional - enabled by default)
    * Bootstrap FluxCD
    * Create service account for AWS EBS CSI Driver and store credentials in a secret
    * Create keys for linkerd / cert manager to use


When Terraform has completed, there will be a `kubeconfig` and `talosconfig` file in your working directory; after about a minute after completion you should have a functional cluster

See `variables.tf` for available variables and descriptions