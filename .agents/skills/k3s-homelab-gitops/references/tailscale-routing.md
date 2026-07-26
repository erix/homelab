# Tailscale routing notes for Erik's k3s homelab

## Intended shape

Use `kaiburg` as a Tailscale **subnet router** for the home/k3s networks:

- `192.168.1.0/24` — main home LAN where `kaiburg` lives.
- `192.168.11.0/24` — k3s/MetalLB network; Traefik is at `192.168.11.200`.

Do **not** use `kaiburg` as an exit node by default. It lacks working IPv6 internet egress, and iOS exit-node use can blackhole general internet traffic (Telegram, web, etc.) when `::/0` is advertised but not actually routable upstream.

Desired client state for accessing homelab services:

- Tailscale connected.
- Exit node: **None**.
- Subnet routes accepted by the client.

Then normal service URLs should work because public DNS resolves them to the MetalLB/Traefik LAN IP:

- `hass.erix-homelab.site -> 192.168.11.200`
- `immich.erix-homelab.site -> 192.168.11.200`
- `paperless.erix-homelab.site -> 192.168.11.200`
- `plex.erix-homelab.site -> 192.168.11.200`

## Server-side commands

Check current Tailscale routing state on `kaiburg`:

```bash
tailscale debug prefs | jq '{AdvertiseRoutes,NoSNAT,NetfilterMode,RunSSH,Hostname}'
tailscale status --json | jq '.Self | {DNSName,HostName,TailscaleIPs,AllowedIPs,PrimaryRoutes,Online}'
```

Set the clean subnet-router-only config:

```bash
sudo tailscale set \
  --advertise-exit-node=false \
  --advertise-routes=192.168.1.0/24,192.168.11.0/24
```

Verify forwarding sysctls when subnet routing is involved:

```bash
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding net.ipv6.conf.default.forwarding
```

Persist if needed:

```bash
sudo tee /etc/sysctl.d/99-tailscale-routing.conf >/dev/null <<'EOF'
# Required for Tailscale subnet routing and exit node relay on kaiburg.
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
sudo sysctl --system
```

Even for subnet routing, enabling IPv6 forwarding is harmless and prevents Tailscale/admin health warnings if exit-node testing is temporarily enabled.

## Exit-node pitfall

Tailscale treats exit nodes as advertising both default routes:

- `0.0.0.0/0`
- `::/0`

On `kaiburg`, IPv4 internet worked but IPv6 internet egress did not. Test with:

```bash
python3 - <<'PY'
import socket
for host, port, fam in [('1.1.1.1',443,socket.AF_INET),('2606:4700:4700::1111',443,socket.AF_INET6)]:
    s=socket.socket(fam, socket.SOCK_STREAM); s.settimeout(3)
    try:
        s.connect((host,port)); print(f'{host}:{port} OK')
    except Exception as e:
        print(f'{host}:{port} FAIL {type(e).__name__}: {e}')
    finally:
        s.close()
PY
```

If IPv6 egress fails, do not recommend `kaiburg` as an exit node for iOS clients. It can make “Tailscale connected but nothing works” because general phone traffic is routed through an incomplete exit path.

## Debugging client subnet-route issues

If a phone cannot access `http://192.168.11.200`:

1. Confirm `kaiburg` has active `PrimaryRoutes` for both subnets.
2. Confirm the phone has Tailscale connected and **Exit Node = None**.
3. Refresh iOS route state: disconnect/reconnect Tailscale; if needed delete/recreate the iOS VPN profile.
4. Check whether traffic reaches `kaiburg` at all:

```bash
sudo iptables -vxnL ts-forward
sudo iptables -t nat -vxnL ts-postrouting
sudo timeout 5 tcpdump -n -i any 'host <PHONE_TAILSCALE_IP> or host 192.168.11.200'
```

If counters/tcpdump stay at zero while the user tests from the phone, the phone is not sending subnet-route traffic to `kaiburg`; focus on client route acceptance, stale iOS VPN state, or Tailscale ACLs.

## Testing note: ping is misleading

`192.168.11.200` (Traefik/MetalLB) did not respond to ICMP ping even from `kaiburg`, while TCP ports 80/443 worked. Do not use ping as the primary test for Traefik/MetalLB reachability.

Use TCP/HTTP tests instead:

```bash
python3 - <<'PY'
import http.client
for host in ['hass.erix-homelab.site','immich.erix-homelab.site','paperless.erix-homelab.site','plex.erix-homelab.site']:
    try:
        c=http.client.HTTPConnection('192.168.11.200',80,timeout=3)
        c.request('GET','/',headers={'Host':host})
        r=c.getresponse()
        print(f'{host}: HTTP {r.status} location={r.getheader("location")}')
        c.close()
    except Exception as e:
        print(f'{host}: FAIL {type(e).__name__}: {e}')
PY
```

## k3s Tailscale Operator role

The k3s Tailscale Operator is installed and useful for selected per-service identities, currently including:

- `default-ib-gateway.tail9139a.ts.net`
- `default-ibeam.tail9139a.ts.net`

Keep this pattern for special services such as trading/IB gateway access. Avoid exposing every Traefik web app individually with `tailscale.com/expose=true`; subnet routing keeps the normal `*.erix-homelab.site` URLs and avoids tailnet machine clutter.
