# Troubleshooting Guide

This document covers common issues encountered when deploying the Talos AWS Terraform cluster and their solutions.

## Table of Contents

- [ArgoCD Deployment Issues](#argocd-deployment-issues)
- [Cluster Connectivity Issues](#cluster-connectivity-issues)
- [Worker Node Issues](#worker-node-issues)
- [Certificate Issues](#certificate-issues)
- [General Debugging](#general-debugging)

---

## ArgoCD Deployment Issues

### Issue: Helm Release Timeout

**Symptoms:**
```
Error: timed out waiting for the condition
Warning: Helm release "argocd" was created but has a failed status.
```

**Root Causes:**
1. No worker nodes available (scaled to 0)
2. Pods cannot schedule due to node taints/tolerations
3. Insufficient timeout configuration
4. Missing resource limits causing OOM issues

**Solutions:**

#### 1. Ensure Worker Nodes are Running

Check your `terraform.tfvars`:
```hcl
worker_nodes_min = 2  # Must be > 0
worker_nodes_max = 3
```

Verify nodes are running:
```bash
kubectl get nodes
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "talos-cluster_workers" \
  --region <your-region> \
  --query 'AutoScalingGroups[0].Instances'
```

#### 2. ArgoCD Configuration Fix

The [post-install/argocd/main.tf](post-install/argocd/main.tf) has been updated with:

- **Explicit timeouts**: 600 seconds (10 minutes)
- **Resource limits**: Prevents OOM kills
- **Removed problematic tolerations**: Allows scheduling on worker nodes
- **Disabled Dex**: Simplifies authentication (can be re-enabled)

```hcl
resource "helm_release" "argocd" {
  timeout          = 600
  wait             = true
  wait_for_jobs    = true
  atomic           = false
  cleanup_on_fail  = false
  
  values = [
    yamlencode({
      # No global tolerations - schedule normally
      server = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      # ... additional resource limits
    })
  ]
}
```

#### 3. Recovery Steps

If ArgoCD deployment fails:

1. **Clean up failed release:**
   ```bash
   kubectl delete namespace argocd
   terraform state rm 'module.post_install.module.argocd[0].kubernetes_namespace.argocd'
   ```

2. **Verify cluster health:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

3. **Redeploy:**
   ```bash
   terraform apply -target='module.post_install.module.argocd[0]'
   ```

---

## Cluster Connectivity Issues

### Issue: Unable to Connect to Kubernetes API

**Symptoms:**
```
Unable to connect to the server: net/http: TLS handshake timeout
```

**Causes:**
1. Outdated kubeconfig
2. Control plane not running
3. Load balancer not healthy
4. Security group blocking access

**Solutions:**

#### 1. Verify Control Plane Health

```bash
# Check control plane instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*control_plane*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'

# Check load balancer target health
aws elbv2 describe-target-health \
  --target-group-arn <your-target-group-arn> \
  --region <your-region>
```

#### 2. Regenerate Kubeconfig

```bash
# Option 1: Via Terraform
terraform refresh -target='module.talos_bootstrap.data.talos_cluster_kubeconfig.kubeconfig'
terraform refresh -target='module.talos_bootstrap.local_file.kubeconfig'

# Option 2: Via Talosctl
talosctl --talosconfig=./talosconfig \
  --nodes <control-plane-endpoint> \
  kubeconfig --force ./kubeconfig

# Use the kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

#### 3. Verify Load Balancer

```bash
# Get LB DNS name
aws elbv2 describe-load-balancers \
  --names talos-cluster \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Test connectivity
curl -k https://<lb-dns-name>:6443
```

---

## Worker Node Issues

### Issue: Worker Nodes Scaled to Zero

**Symptoms:**
- Pods stuck in `Pending` state
- `kubectl get nodes` shows only control plane
- ArgoCD/workloads fail to deploy

**Root Cause:**
`terraform.tfvars` configured with:
```hcl
worker_nodes_min = 0
worker_nodes_max = 0
```

**Solution:**

1. **Update Configuration:**
   ```hcl
   # In terraform.tfvars
   worker_nodes_min = 2
   worker_nodes_max = 3
   ```

2. **Apply Changes:**
   ```bash
   terraform apply -target='module.compute.aws_autoscaling_group.worker'
   ```

3. **Wait for Nodes to Join:**
   ```bash
   # Wait ~2-3 minutes, then check
   kubectl get nodes -w
   ```

4. **Verify Node Readiness:**
   ```bash
   kubectl get nodes -o wide
   kubectl describe node <node-name>
   ```

### Issue: Nodes Not Ready

**Symptoms:**
```
NAME     STATUS     ROLES    AGE   VERSION
node-1   NotReady   <none>   5m    v1.30.5
```

**Common Causes:**
1. CNI (Cilium) not running
2. Kubelet issues
3. Network connectivity problems

**Solutions:**

#### Check Cilium Status
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium --tail=50
```

#### Check Node Conditions
```bash
kubectl describe node <node-name> | grep -A 10 Conditions
```

#### Via Talosctl
```bash
talosctl --talosconfig=./talosconfig \
  --nodes <node-ip> \
  services
```

---

## Certificate Issues

### Issue: Certificate Signed by Unknown Authority

**Symptoms:**
```
rpc error: tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Causes:**
- Talosconfig/kubeconfig out of sync with cluster
- Cluster was rebuilt but configs weren't regenerated
- Clock skew on local machine

**Solutions:**

1. **Regenerate All Configs:**
   ```bash
   terraform apply -target='module.talos_config'
   terraform apply -target='module.talos_bootstrap'
   ```

2. **Verify Certificate Expiry:**
   ```bash
   # Check kubeconfig certificate
   kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | \
     base64 -d | openssl x509 -text -noout | grep -A 2 Validity
   ```

3. **Full Refresh:**
   ```bash
   terraform refresh
   ```

---

## General Debugging

### Useful Commands

#### Cluster Status
```bash
# Kubernetes
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'

# Talos
talosctl --talosconfig=./talosconfig health
talosctl --talosconfig=./talosconfig dashboard
talosctl --talosconfig=./talosconfig logs kubelet
```

#### AWS Resources
```bash
# List all cluster resources
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=talos-cluster*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' \
  --output table

# ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "talos-cluster_control_plane" "talos-cluster_workers"

# Load balancer health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names talos-cluster \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
```

#### Terraform State
```bash
# List resources
terraform state list

# Inspect specific resource
terraform state show 'module.compute.aws_autoscaling_group.worker'

# Remove stuck resource
terraform state rm 'resource.path'
```

### Logs and Events

#### ArgoCD Logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

#### System Logs via Talosctl
```bash
talosctl --talosconfig=./talosconfig logs controller-runtime
talosctl --talosconfig=./talosconfig logs kubelet
talosctl --talosconfig=./talosconfig dmesg
```

### Common Fixes

#### Reset Failed Deployment

```bash
# 1. Remove namespace
kubectl delete namespace <namespace> --wait=true

# 2. Remove from Terraform state if needed
terraform state rm 'module.path.to.resource'

# 3. Reapply
terraform apply -target='module.path.to.resource'
```

#### Force Terraform Refresh

```bash
# Refresh all state
terraform refresh

# Or target specific modules
terraform refresh -target='module.talos_bootstrap'
```

#### Emergency Cluster Access

If kubeconfig is broken but cluster is running:

```bash
# Get control plane IP
CONTROL_PLANE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*control_plane*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Generate new kubeconfig via Talosctl
talosctl --talosconfig=./talosconfig \
  --nodes $CONTROL_PLANE_IP \
  kubeconfig --force ./kubeconfig-emergency

export KUBECONFIG=./kubeconfig-emergency
```

---

## Prevention Best Practices

### Before Deployment

1. **Verify Configuration:**
   ```bash
   terraform plan | grep -E "(worker_nodes|control_plane_nodes)"
   ```

2. **Check Prerequisites:**
   - AWS credentials configured
   - Sufficient EC2 limits
   - VPC CIDR doesn't conflict

3. **Use Remote State:**
   ```bash
   cd bootstrap-backend
   terraform apply
   # Then enable in backend.tf
   ```

### During Deployment

1. **Monitor Progress:**
   ```bash
   # Terminal 1: Terraform
   terraform apply

   # Terminal 2: Watch cluster
   watch kubectl get nodes,pods -A
   ```

2. **Save Outputs:**
   ```bash
   terraform output > outputs.txt
   ```

### After Deployment

1. **Verify Health:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   talosctl health
   ```

2. **Backup Configs:**
   ```bash
   cp kubeconfig kubeconfig.backup
   cp talosconfig talosconfig.backup
   ```

3. **Test Workload:**
   ```bash
   kubectl run test --image=nginx --rm -it -- /bin/sh
   ```

---

## Getting Help

### Collect Debug Information

```bash
#!/bin/bash
# debug-collect.sh

echo "=== Terraform State ===="
terraform state list

echo -e "\n=== AWS Instances ===="
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=talos-cluster*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'

echo -e "\n=== Kubernetes Nodes ===="
kubectl get nodes -o wide

echo -e "\n=== Pods ===="
kubectl get pods -A

echo -e "\n=== Events ===="
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

echo -e "\n=== Talos Health ===="
talosctl --talosconfig=./talosconfig health
```

Run with:
```bash
chmod +x debug-collect.sh
./debug-collect.sh > debug-output.txt 2>&1
```

### Additional Resources

- [Talos Documentation](https://talos.dev/docs/)
- [ArgoCD Troubleshooting](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)
- [Cilium Troubleshooting](https://docs.cilium.io/en/stable/operations/troubleshooting/)

---

## Changelog of Fixes

### 2026-02-15: ArgoCD Deployment Fix

**Changes Made:**
- Added explicit timeouts (600s) to ArgoCD Helm release
- Removed problematic node tolerations
- Added resource limits for all ArgoCD components
- Disabled Dex for simplified authentication
- Set `atomic=false` and `cleanup_on_fail=false` for debugging

**Files Modified:**
- `post-install/argocd/main.tf`
- `terraform.tfvars` (local changes required)

**Impact:**
- ArgoCD now deploys successfully with 2+ worker nodes
- Pods schedule properly without taint issues
- Resource constraints prevent OOM kills
