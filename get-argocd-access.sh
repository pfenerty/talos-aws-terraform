#!/bin/bash
# Get Argo CD Access Information

set -e

echo "=== Argo CD Access Information ==="
echo ""

# Check if argocd namespace exists
if ! kubectl get namespace argocd &>/dev/null; then
    echo "Error: Argo CD is not installed (argocd namespace not found)"
    echo "Enable it in terraform.tfvars and run: terraform apply"
    exit 1
fi

# Get LoadBalancer URL
echo "Getting Argo CD Server URL..."
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$ARGOCD_URL" ]; then
    echo "⏳ LoadBalancer is still provisioning..."
    echo "Run this command to wait: kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' svc/argocd-server -n argocd --timeout=300s"
    echo ""
    ARGOCD_URL="<pending>"
else
    echo "✅ Argo CD URL: http://$ARGOCD_URL"
    echo ""
fi

# Get admin password
echo "Getting admin password..."
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<not-ready>")

if [ "$ADMIN_PASSWORD" = "<not-ready>" ]; then
    echo "⏳ Admin secret not ready yet..."
else
    echo "✅ Admin Username: admin"
    echo "✅ Admin Password: $ADMIN_PASSWORD"
fi

echo ""
echo "=== Access Instructions ==="
if [ "$ARGOCD_URL" != "<pending>" ]; then
    echo "Open in browser: http://$ARGOCD_URL"
    echo ""
    echo "Note: It may take 2-3 minutes for the LoadBalancer to become available"
    echo "      after Terraform completes."
else
    echo "Wait for LoadBalancer, then run this script again."
fi
