# Talos Linux AWS Kubernetes Terraform

Terraform code for creating a Kubernetes cluster in AWS using [Talos Linux](https://talos.dev)

This was created mostly by translating the AWS CLI commands in the [Talos docs](https://www.talos.dev/v1.3/talos-guides/install/cloud-platforms/aws/)

Terraform will:

1. Create Talos machine configs

2. Create AWS infrastructure and apply machine configs to appropriate servers

3. Bootstrap the cluster

When Terraform has completed, there will be a `kubeconfig` and `talosconfig` file in your working directory; after about a minute after completion you should have a functional cluster

See `variables.tf` for available variables and descriptions