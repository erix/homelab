# Tailscale Kubernetes Operator

Exposes cluster services to your Tailnet using the official [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator).

Managed via **Helm** (`tailscale/tailscale-operator`).

## Prerequisites

- `helm` and `kubectl` configured for the cluster
- SealedSecrets controller running (for OAuth credential management)
- Tailscale OAuth credentials sealed in `operator-oauth-sealed.yaml`

## Install / Re-install

```bash
cd infrastructure/tailscale
./install.sh
```

The script:
1. Applies the SealedSecret (decrypted in-cluster, never plaintext in git)
2. Extracts the OAuth credentials from the decrypted secret
3. Installs/upgrades the Helm release
4. Applies service annotations for exposed services

## Upgrade

```bash
helm repo update tailscale
helm upgrade tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --values values.yaml \
  --reuse-values
```

## Check Status

```bash
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/operator --tail=30

# Check Tailscale admin console for connected devices:
# https://login.tailscale.com/admin/machines
```

## Exposing Services

Add this annotation to any Service to expose it on your Tailnet:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    # tailscale.com/hostname: "my-service"   # optional custom hostname
```

Or apply the pre-configured patches in this directory (e.g. `ib-gateway-service-patch.yaml`).

## Recreating the OAuth Secret

If you need to re-seal fresh OAuth credentials:

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Create a new OAuth client with `tag:k8s`
3. Create `operator-secret.yaml` (do **not** commit this):

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: operator-oauth
     namespace: tailscale
   stringData:
     client_id: "YOUR_CLIENT_ID"
     client_secret: "YOUR_CLIENT_SECRET"
   ```

4. Seal it:

   ```bash
   kubeseal -f operator-secret.yaml -w operator-oauth-sealed.yaml
   rm operator-secret.yaml
   ```

5. Commit the updated `operator-oauth-sealed.yaml`.
