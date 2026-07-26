# Tailscale Access Patterns for k3s Homelab

Use this reference when deciding how to make homelab services reachable over Tailscale.

## Observed baseline

- Tailscale Kubernetes Operator runs in namespace `tailscale` as Helm release `tailscale-operator`.
- The operator creates/uses `IngressClass/tailscale` and supports service exposure through annotations.
- `kaiburg` also runs host-level Tailscale (`tailscaled`) and can act as a subnet router if routes are advertised and approved in the Tailscale admin console.
- Homelab ingress DNS names such as `hass.erix-homelab.site`, `immich.erix-homelab.site`, `plex.erix-homelab.site`, and `paperless.erix-homelab.site` resolve to Traefik/MetalLB on `192.168.11.200`.

## Pattern A: expose individual Kubernetes Services

Use for a small number of sensitive services or raw TCP services.

Add to the Service manifest, preferably in GitOps rather than live-only `kubectl annotate`:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    # tailscale.com/hostname: "my-service" # optional custom tailnet hostname
```

Verify:

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl
$K get svc -A -o json | jq -r '.items[] | select(.metadata.annotations."tailscale.com/expose" == "true") | [.metadata.namespace,.metadata.name,.spec.type] | @tsv'
$K -n tailscale get pods -o wide
$K -n tailscale exec <ts-proxy-pod> -c tailscale -- tailscale status --json | jq '{Self:{DNSName:.Self.DNSName,TailscaleIPs:.Self.TailscaleIPs,Online:.Self.Online},BackendState:.BackendState}'
```

## Pattern B: expose Traefik through Tailscale

Use when the user wants a Tailscale entrypoint for many existing web apps while keeping Kubernetes-native ingress routing. This is broader than exposing one Service but narrower than routing the whole LAN.

Consider exposing Traefik's Service or creating a dedicated Tailscale ingress, then verify host header routing to existing `*.erix-homelab.site` names.

## Pattern C: host-level subnet routing

Use when the user wants devices on the tailnet to access homelab services as if they were on the LAN.

Typical routes for Erik's current layout:

```bash
sudo tailscale set --advertise-routes=192.168.1.0/24,192.168.11.0/24
```

Then the user must approve the routes:

```text
Tailscale Admin Console -> Machines -> kaiburg -> Edit route settings -> approve routes
```

Client-side note: Linux clients may need:

```bash
sudo tailscale set --accept-routes=true
```

macOS/iOS/Android usually accept approved subnet routes through the GUI/client settings.

Preflight checks before enabling subnet routing:

```bash
tailscale debug prefs | jq '{AdvertiseRoutes,AdvertiseExitNode,NoSNAT,NetfilterMode}'
cat /proc/sys/net/ipv4/ip_forward
ip route
getent ahostsv4 hass.erix-homelab.site immich.erix-homelab.site
```

Post-approval verification from a tailnet client:

```bash
curl -kI https://hass.erix-homelab.site
curl -kI https://immich.erix-homelab.site
curl -kI https://paperless.erix-homelab.site
```

## Decision rule

- Few raw services: Pattern A.
- Existing web apps via Kubernetes ingress only: Pattern B.
- "I want my homelab reachable like I am at home": Pattern C.

Avoid exposing everything service-by-service when subnet routing or a Traefik entrypoint better matches the user's goal.
