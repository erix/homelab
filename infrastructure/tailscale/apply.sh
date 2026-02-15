#!/bin/bash
set -e

echo "=== Installing Tailscale Kubernetes Operator ==="
echo ""

# Check if sealed secret exists
if [ ! -f "operator-oauth-sealed.yaml" ]; then
    echo "⚠️  ERROR: operator-oauth-sealed.yaml not found"
    echo ""
    echo "You need to create a sealed secret first:"
    echo "1. Edit operator-secret.yaml with your OAuth credentials"
    echo "2. Run: kubeseal -f operator-secret.yaml -w operator-oauth-sealed.yaml"
    echo ""
    exit 1
fi

echo "Step 1: Creating namespace..."
kubectl apply -f namespace.yaml

echo ""
echo "Step 2: Creating OAuth sealed secret..."
kubectl apply -f operator-oauth-sealed.yaml

echo ""
echo "Step 3: Setting up RBAC..."
kubectl apply -f operator-rbac.yaml

echo ""
echo "Step 4: Deploying Tailscale operator..."
kubectl apply -f operator-deployment.yaml

echo ""
echo "Step 5: Waiting for operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/operator -n tailscale

echo ""
echo "Step 6: Updating ib-gateway service with Tailscale annotation..."
kubectl apply -f ib-gateway-service-patch.yaml

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Monitor the operator:"
echo "  kubectl logs -n tailscale -l app=operator -f"
echo ""
echo "Check ib-gateway Tailscale proxy:"
echo "  kubectl get statefulsets -A | grep ib-gateway"
echo "  kubectl get svc ib-gateway -n default -o jsonpath='{.metadata.annotations.tailscale\.com/hostname}'"
echo ""
echo "The service should be accessible at: ib-gateway.<your-tailnet>.ts.net"
