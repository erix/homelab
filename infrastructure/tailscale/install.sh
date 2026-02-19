#!/bin/bash
# Install (or upgrade) the Tailscale Kubernetes Operator via Helm.
# OAuth credentials are extracted from the SealedSecret in this directory —
# never stored in plaintext in the repo.
set -euo pipefail

NAMESPACE="tailscale"
RELEASE="tailscale-operator"
CHART="tailscale/tailscale-operator"

echo "=== Tailscale Operator Helm Install ==="
echo ""

# Add Helm repo if needed
if ! helm repo list 2>/dev/null | grep -q tailscale; then
  echo "Adding Tailscale Helm repo..."
  helm repo add tailscale https://pkgs.tailscale.com/helmcharts
fi
helm repo update tailscale

# Create namespace (idempotent)
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"

# Apply the SealedSecret so the controller decrypts the OAuth credentials.
# The sealed secret is safe to store in git — it's encrypted with the cluster key.
echo ""
echo "Applying sealed OAuth secret..."
kubectl apply -f operator-oauth-sealed.yaml

echo "Waiting for SealedSecrets controller to decrypt..."
for i in $(seq 1 20); do
  if kubectl get secret operator-oauth -n "$NAMESPACE" &>/dev/null; then
    echo "Secret ready."
    break
  fi
  sleep 2
done

# Extract credentials
CLIENT_ID=$(kubectl get secret operator-oauth -n "$NAMESPACE" -o jsonpath='{.data.client_id}' | base64 -d)
CLIENT_SECRET=$(kubectl get secret operator-oauth -n "$NAMESPACE" -o jsonpath='{.data.client_secret}' | base64 -d)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "ERROR: Could not extract OAuth credentials from secret."
  exit 1
fi

# Remove the manually-created secret — Helm will own its own copy
kubectl delete secret operator-oauth -n "$NAMESPACE" --ignore-not-found
kubectl delete sealedsecret operator-oauth -n "$NAMESPACE" --ignore-not-found

echo ""
echo "Installing/upgrading Helm release..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values values.yaml \
  --set-string oauth.clientId="$CLIENT_ID" \
  --set-string oauth.clientSecret="$CLIENT_SECRET" \
  --wait --timeout=120s

echo ""
echo "=== Done! ==="
echo ""
echo "Verify:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE deployment/operator --tail=20"
echo ""
echo "Then apply service annotations:"
echo "  kubectl apply -f ib-gateway-service-patch.yaml"
