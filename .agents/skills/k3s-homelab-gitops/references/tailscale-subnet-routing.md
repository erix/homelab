# Tailscale subnet routing and exit-node troubleshooting

Use this when Erik wants homelab/k3s services reachable from phones/laptops over Tailscale without exposing each Kubernetes Service individually.

## Known-good intent

For Erik's current homelab shape, the practical subnet-router target is usually:

- `192.168.1.0/24` — kaiburg's LAN segment.
- `192.168.11.0/24` — k3s/MetalLB service segment; Traefik is commonly `192.168.11.200`.

A subnet router is enough for `hass.erix-homelab.site -> 192.168.11.200`; an exit node is not required for normal split-DNS/public DNS resolution. Exit nodes route all client traffic and are more fragile.

## Server-side checks on kaiburg

```bash
tailscale debug prefs | jq '{AdvertiseRoutes,NoSNAT,NetfilterMode}'
tailscale status --json | jq '.Self | {DNSName,TailscaleIPs,AllowedIPs,PrimaryRoutes,Online}'
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding net.ipv6.conf.default.forwarding
sudo iptables -vxnL FORWARD
sudo iptables -vxnL ts-forward
sudo iptables -t nat -vxnL ts-postrouting
```

`AllowedIPs`/`PrimaryRoutes` must include the approved subnet routes. If `AdvertiseRoutes` has routes but `PrimaryRoutes` does not, the Tailscale admin console has not approved them yet.

## Enable subnet routing

```bash
sudo tailscale set --advertise-routes=192.168.1.0/24,192.168.11.0/24
```

Then approve the routes in Tailscale admin:

`Machines -> kaiburg -> Edit route settings -> approve 192.168.1.0/24 and 192.168.11.0/24`.

Persist forwarding for reboot:

```bash
sudo install -m 0644 /dev/stdin /etc/sysctl.d/99-tailscale-routing.conf <<'EOF'
# Required for Tailscale subnet routing and exit node relay on kaiburg.
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
sudo sysctl --system
```

Restarting `tailscaled` can refresh stale admin-console health checks after enabling forwarding:

```bash
sudo systemctl restart tailscaled
```

## Client-side checks

If the phone/client cannot reach `http://192.168.11.200`, DNS is not the issue; the client is not using the subnet route.

For iOS/Android:

1. Confirm Tailscale app says Connected.
2. Toggle Tailscale off/on after route approval.
3. Test on cellular with Wi-Fi off to avoid local-network ambiguity.
4. Test direct `http://192.168.11.200` before testing `https://hass.erix-homelab.site`.

For Linux clients:

```bash
sudo tailscale set --accept-routes=true
```

From kaiburg, `tailscale status --json` may show iOS clients as offline if they are asleep/backgrounded; do not over-interpret that alone. Packet counters on `ts-forward` are better evidence of whether client traffic is arriving.

## Exit-node pitfalls

Exit node is not needed for homelab service access. Only enable it when Erik explicitly wants all internet traffic routed through home.

Tailscale advertises exit nodes as both `0.0.0.0/0` and `::/0`. If kaiburg has no working IPv6 internet egress, iOS may appear connected but internet access can break when selecting the exit node because IPv6 traffic is blackholed. Verify before offering exit-node use:

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

If exit-node selection breaks the phone, remove exit-node advertisement while keeping subnet routes:

```bash
sudo tailscale set --advertise-exit-node=false --advertise-routes=192.168.1.0/24,192.168.11.0/24
```

Check that `AdvertiseRoutes` no longer includes `0.0.0.0/0` or `::/0`.

## Quick service verification

From kaiburg, confirm Traefik/LAN still works after any Tailscale change:

```bash
python3 - <<'PY'
import http.client
for host in ['hass.erix-homelab.site','immich.erix-homelab.site','paperless.erix-homelab.site']:
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
