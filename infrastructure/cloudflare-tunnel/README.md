# Cloudflare Tunnel

Exposes selected internal services to the internet via Cloudflare Tunnel — no open ports, proper TLS, custom domain.

## Architecture

```
Internet → Cloudflare Tunnel → cloudflared (namespace: tunnel) → Traefik → App Service
```

- One `cloudflared` deployment in the `tunnel` namespace handles all public services
- Traefik routes by hostname as normal — no changes needed to existing apps
- What's public is controlled entirely by the Cloudflare remote ingress config (not in git)

## Tunnel Details

- **Tunnel ID:** `c7f98048-9d70-4db8-a8b7-7345362872c2`
- **Tunnel name:** `splitbot`
- **Cloudflare account:** `94351562de53565639b6daca69de7d9c`
- **Credentials:** stored as SealedSecret `cloudflared-tunnel-secret` in `tunnel` namespace
- **k8s manifests:** `~/Projects/splitbot/k8s/tunnel/`
- **Flux kustomization:** `clusters/new/apps/tunnel.yaml`

## Exposing a New Service

### 1. Add an Ingress in the app's namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
spec:
  ingressClassName: traefik
  rules:
    - host: myapp.erix-homelab.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

### 2. Add the hostname to the Cloudflare tunnel ingress config

Get the API token from `~/.cloudflared/cert.pem`:

```bash
CERT=$(cat ~/.cloudflared/cert.pem | grep -v "BEGIN\|END" | tr -d '\n')
DECODED=$(echo $CERT | base64 -d)
ACCOUNT_ID=$(echo $DECODED | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['accountID'])")
API_TOKEN=$(echo $DECODED | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['apiToken'])")
```

Then update the ingress config (replace the full `ingress` array — order matters, catch-all must be last):

```bash
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/c7f98048-9d70-4db8-a8b7-7345362872c2/configurations" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "config": {
      "ingress": [
        {
          "hostname": "splitbot.erix-homelab.site",
          "service": "http://traefik.kube-system.svc.cluster.local:80"
        },
        {
          "hostname": "myapp.erix-homelab.site",
          "service": "http://traefik.kube-system.svc.cluster.local:80"
        },
        {
          "service": "http_status:404"
        }
      ]
    }
  }'
```

All hostnames point to the same Traefik service — Traefik handles routing by `Host` header.

## Stopping Public Access

Scale cloudflared to 0 (bot/apps keep running internally):

```bash
kubectl scale deployment cloudflared -n tunnel --replicas=0
# Restore:
kubectl scale deployment cloudflared -n tunnel --replicas=1
```

## Re-sealing the Tunnel Token

If the cluster changes or the SealedSecret needs to be recreated:

```bash
TUNNEL_TOKEN="<token from cloudflared tunnel token c7f98048-9d70-4db8-a8b7-7345362872c2>"
echo -n "$TUNNEL_TOKEN" | kubeseal --raw \
  --namespace tunnel \
  --name cloudflared-tunnel-secret \
  --from-file=/dev/stdin
```

Paste the output into `k8s/tunnel/overlays/local/tunnel-sealed.yaml` in the splitbot repo.
