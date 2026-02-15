# Tailscale Kubernetes Operator

This directory contains the Tailscale Kubernetes Operator setup for exposing services to your Tailnet.

## Setup Instructions

### 1. Create Tailscale OAuth Credentials

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Click "Generate OAuth client"
3. Add the following tags: `tag:k8s`
4. Copy the Client ID and Client Secret

### 2. Update the Secret

Edit `operator-secret.yaml` and add your OAuth credentials:

```yaml
stringData:
  client_id: "YOUR_CLIENT_ID"
  client_secret: "YOUR_CLIENT_SECRET"
```

### 3. Apply the Manifests

```bash
kubectl apply -f namespace.yaml
kubectl apply -f operator-secret.yaml
kubectl apply -f operator-rbac.yaml
kubectl apply -f operator-deployment.yaml
```

### 4. Verify Installation

```bash
kubectl get pods -n tailscale
kubectl logs -n tailscale -l app=operator
```

## Exposing Services

To expose a service to Tailscale, add this annotation:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
```

The operator will automatically create a Tailscale proxy and assign a hostname.

## Example: ib-gateway

The ib-gateway service is already configured with Tailscale annotations.
After applying the operator, it will be accessible at: `ib-gateway.tailnet-XXXX.ts.net`

Check the service for the assigned hostname:

```bash
kubectl get svc ib-gateway -n default -o yaml | grep tailscale
```

## Troubleshooting

```bash
# Check operator logs
kubectl logs -n tailscale -l app=operator -f

# Check if StatefulSet was created for the proxy
kubectl get statefulsets -A | grep ib-gateway

# Check proxy pod logs
kubectl logs -n default sts/ts-ib-gateway-ib-gateway
```
