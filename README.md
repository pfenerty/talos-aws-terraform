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
        * Creates keys for linkerd / cert manager to use
        * Creates config secrets for autoscaler
    * Installs Cilium and creates keys for hubble to use cert-manager


When Terraform has completed, there will be a `kubeconfig` and `talosconfig` file in your working directory; after about a minute after completion you should have a functional cluster

See `variables.tf` for available variables and descriptions