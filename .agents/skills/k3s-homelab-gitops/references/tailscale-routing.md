# Tailscale routing for a k3s homelab

Use this reference when clients need private access to Kubernetes ingress, MetalLB addresses, or LAN services through Tailscale.

Do not assume the agent is running on the subnet router, that the router has a particular hostname, or that example CIDRs are correct. Discover all three layers independently:

1. Kubernetes Service/Ingress addresses.
2. Host routing and forwarding state on the proposed subnet router.
3. Tailnet route approval and client route acceptance.

## Choose the access model

- **Per-service exposure:** annotate selected Services for the Tailscale Kubernetes operator. Best for a small number of explicit services.
- **Ingress exposure:** expose an ingress controller or use a Tailscale ingress class. Best when existing host-based routing should remain central.
- **Subnet routing:** advertise the LAN and/or MetalLB CIDRs from a Tailscale node. Best for LAN-like access to many existing services.
- **Exit node:** advertise default routes for all internet traffic. Not required for homelab service access and unsafe unless both IPv4 and IPv6 egress work.

## Discover Kubernetes networks and endpoints

```bash
"$K" get nodes -o wide
"$K" get svc -A -o wide
"$K" get ingress -A -o wide
"$K" get ipaddresspools.metallb.io -A -o yaml 2>/dev/null || true
"$K" get svc -A -o json \
  | jq -r '.items[] | select(.status.loadBalancer.ingress) | [.metadata.namespace,.metadata.name,([.status.loadBalancer.ingress[] | (.ip // .hostname)] | join(","))] | @tsv'
```

Derive `LAN_CIDR`, `SERVICE_CIDR`, `INGRESS_IP`, and representative `INGRESS_HOST` from current routing, manifests, DNS, and live Services. Do not copy them blindly from old documentation.

## Discover the candidate subnet router

Run these checks **on the proposed router host**, whether reached locally, through SSH, CI, or another agent gateway:

```bash
hostname -f 2>/dev/null || hostname
command -v tailscale
command -v ip

tailscale status
tailscale debug prefs | jq '{AdvertiseRoutes,AdvertiseExitNode,RouteAll,NoSNAT,NetfilterMode}'
ip -4 route
ip -6 route
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
```

Record the execution host and observed routes in the task summary. If the harness cannot prove it is running on the intended router, do not run `sudo tailscale set`.

## Advertise subnet routes

Set discovered values explicitly:

```bash
LAN_CIDR='<discovered-lan-cidr>'
SERVICE_CIDR='<discovered-k3s-or-metallb-cidr>'

sudo tailscale set --advertise-routes="$LAN_CIDR,$SERVICE_CIDR"
tailscale debug prefs | jq '{AdvertiseRoutes,AdvertiseExitNode}'
```

Advertising does not activate routes by itself. An administrator must approve them in the Tailscale admin console. Verify activation without assuming a specific machine name:

```bash
tailscale status --json \
  | jq '.Self | {HostName,DNSName,TailscaleIPs,AllowedIPs,PrimaryRoutes,Online}'
```

Interpretation:

- `AdvertiseRoutes` contains the requested CIDRs: the node is offering them.
- `PrimaryRoutes` contains the CIDRs: the tailnet has approved/selected them.
- Missing `PrimaryRoutes`: stop and request route approval; do not compensate by changing Kubernetes Services.

## Verify forwarding and client traffic

On Linux, IPv4 forwarding must be enabled. Follow the host's configuration-management method rather than making an undocumented permanent sysctl change.

```bash
sysctl net.ipv4.ip_forward
sudo nft list ruleset 2>/dev/null | grep -i tailscale || true
sudo iptables -L FORWARD -n -v 2>/dev/null || true
sudo iptables -L ts-forward -n -v 2>/dev/null || true
```

Ask the client to make one bounded request while watching counters or a narrow packet capture:

```bash
CLIENT_TS_IP='<client-tailscale-ip>'
INGRESS_IP='<discovered-ingress-or-service-ip>'

sudo timeout 10 tcpdump -n -i any \
  "host $CLIENT_TS_IP and host $INGRESS_IP"
```

If no packets arrive, focus on route approval, client `accept-routes`, ACL/grant policy, conflicting VPNs, and stale mobile VPN state. If packets arrive but no response returns, inspect forwarding/firewall and the destination service.

## Test the actual protocol

ICMP can fail while HTTP/HTTPS succeeds. Test direct TCP first, then host-based routing:

```bash
INGRESS_IP='<discovered-ingress-ip>'
INGRESS_HOST='<discovered-ingress-hostname>'

curl -fsSI --max-time 5 "http://$INGRESS_IP/" || true
curl -kfsSI --max-time 10 \
  --resolve "$INGRESS_HOST:443:$INGRESS_IP" \
  "https://$INGRESS_HOST/"
```

For a non-HTTP service, test its real TCP/UDP protocol rather than substituting ping.

## Exit-node safety

Enable exit-node advertisement only when the user explicitly wants all client internet traffic routed through this node and both families have working egress:

```bash
curl -4fsS --max-time 10 https://ifconfig.co >/dev/null
curl -6fsS --max-time 10 https://ifconfig.co >/dev/null
```

If either required path fails, do not advertise an exit node. Subnet routes remain sufficient for homelab access.

When requirements are met:

```bash
sudo tailscale set \
  --advertise-exit-node \
  --advertise-routes="$LAN_CIDR,$SERVICE_CIDR"
```

Rollback exit-node advertisement without dropping subnet access:

```bash
sudo tailscale set \
  --advertise-exit-node=false \
  --advertise-routes="$LAN_CIDR,$SERVICE_CIDR"
```

Verify the intended flags afterward; never infer success from command exit alone.

## Kubernetes operator checks

Per-service exposure is separate from host subnet routing:

```bash
"$K" get svc -A -o json \
  | jq -r '.items[] | select(.metadata.annotations."tailscale.com/expose" == "true") | [.metadata.namespace,.metadata.name] | @tsv'
"$K" get pods -n tailscale -o wide
```

If Flux owns a Service, commit exposure annotations to Git rather than leaving a live-only mutation.

## Completion criteria

- [ ] Access model was chosen explicitly.
- [ ] Router host identity and routes were discovered, not assumed.
- [ ] Advertised and approved routes match current LAN/service CIDRs.
- [ ] Client accepts routes and sends packets to the router.
- [ ] Forwarding/firewall allows the path.
- [ ] Direct service or ingress IP works over the actual protocol.
- [ ] Host-based routing and TLS work where applicable.
- [ ] Exit-node advertisement remains off unless IPv4 and IPv6 egress requirements pass.
- [ ] Any Kubernetes exposure change is represented in GitOps and reconciled.
