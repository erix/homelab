# Pi-hole

Network-wide ad blocking via DNS.

## Deployment

Deployed via Helm chart `mojo2600/pihole`:

```bash
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm install pihole mojo2600/pihole --version 2.38.0 -f values.yaml
```

## Services

| Service | Type | IP | Ports |
|---------|------|-----|-------|
| pihole-dns | LoadBalancer | 192.168.11.222 | 53/TCP, 53/UDP |
| pihole-web | ClusterIP | - | 80, 443 |
| pihole-dhcp | NodePort | - | 67/UDP |

## Components

- **pihole**: Pi-hole DNS sinkhole (`pihole/pihole:2026.07.2`, pinned by OCI digest)
- **cloudflared**: DNS-over-HTTPS sidecar → Cloudflare 1.1.1.1

The current Helm release uses chart `pihole-2.38.0`. The Deployment uses the
`Recreate` strategy so two Pi-hole instances never write the same SQLite-backed
configuration PVC during an upgrade.

## Ingress

Web UI available at: https://pihole.erix-homelab.site

## Troubleshooting

Check blocking status:
```bash
kubectl exec $(kubectl get pod -l app=pihole -o jsonpath='{.items[0].metadata.name}') -c pihole -- pihole status
```

Enable blocking if disabled:
```bash
kubectl exec <pod> -c pihole -- pihole enable
```
