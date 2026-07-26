# Staging custom domains for a private k3s website

Use this workflow when a website already runs behind the homelab Traefik ingress and the user wants its real domains configured locally before exposing exactly that site to the internet.

## Safe staging pattern

1. Discover the existing Ingress, Service, endpoint, Flux Kustomization, current public DNS, and authoritative nameservers.
2. Keep the existing trusted internal hostname and TLS Ingress unchanged.
3. Add a **separate HTTP-only Ingress** for the real domains, restricted to Traefik's `web` entrypoint. Route each Host rule to the same ClusterIP Service.
4. Add Pi-hole split-DNS records for the real domains pointing to Traefik's LAN address. Preserve the complete existing `dnsmasq.additionalHostsEntries` array: Helm list overrides replace the entire list.
5. Commit the new Ingress through GitOps, reconcile Flux, and verify the applied revision.
6. Test each hostname with `curl --resolve <host>:80:<traefik-lan-ip>` and compare the response body hash against the original website. This proves Host routing and content equality independently of resolver caches.

Example staged Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site-custom-domains
  namespace: site
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: site
                port:
                  number: 80
    - host: www.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: site
                port:
                  number: 80
```

## TLS and DNS provider checks

Before adding a Certificate, compare the domain's authoritative nameservers with the configured cert-manager DNS-01 solver:

- A Cloudflare DNS-01 issuer cannot validate a zone still authoritative on Namecheap merely because the resulting A record points at a Cloudflare IP.
- Reusing a wildcard certificate for another zone causes a browser hostname mismatch.
- Do not create a permanently failing Certificate or expose shared Traefik ports just to satisfy HTTP-01 during staging.
- During the private stage, clearly report that the real domains are HTTP-only on the LAN while the original internal hostname retains trusted HTTPS.

## Public stage

For exactly one public static site, prefer a dedicated Cloudflare Tunnel routed directly to that site's ClusterIP Service. Do not route it through shared Traefik and do not forward router ports 80/443. Move or delegate authoritative DNS as required by the tunnel/certificate provider, then configure both apex and `www` at the edge. Keep Pi-hole split DNS only if local direct routing remains desirable.

## Verification checklist

- [ ] Existing internal HTTPS hostname still returns 200.
- [ ] Apex and `www` resolve to Traefik only through Pi-hole during staging.
- [ ] Separate custom-domain Ingress is LAN HTTP-only.
- [ ] All Host routes return byte-identical content.
- [ ] Flux Kustomization is Ready at the pushed revision.
- [ ] No public DNS record points at the home WAN/Traefik before the tunnel stage.
- [ ] No router port-forward was introduced.
