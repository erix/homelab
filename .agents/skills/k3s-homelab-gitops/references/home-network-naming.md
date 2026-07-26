# Home Network Naming and Single-Service Public Exposure

## Pi-hole local DNS pattern

Pi-hole is deployed as Helm release `default/pihole` (chart `mojo2600/pihole`), with its DNS LoadBalancer at `192.168.11.222`. At the time of writing, Pi-hole DHCP is disabled (`dhcp.active=false`), so DHCP reservations must be configured on the LAN gateway/UniFi controller rather than in Pi-hole.

Use `home.arpa` for manually managed home names; do not use `.local` because it conflicts with mDNS/Bonjour.

For a static local DNS name, keep the Helm release configuration declarative through:

```yaml
dnsmasq:
  additionalHostsEntries:
    - "<LAN-IP> <hostname>.home.arpa <hostname>"
```

Apply conservatively and verify both the deployment rollout and Pi-hole itself:

```bash
helm upgrade pihole mojo2600/pihole --version <current-chart-version> \
  --namespace default --reuse-values --values <override.yaml> --wait --timeout 180s
kubectl -n default rollout status deployment/pihole --timeout=180s
kubectl -n default exec <pihole-pod> -c pihole -- nslookup <hostname>.home.arpa 127.0.0.1
```

Test the Pi-hole server directly. A host can have a public fallback resolver configured (for example `1.1.1.1`) that makes normal system resolution of a private zone appear to fail even when Pi-hole correctly serves the record.

First create a DHCP reservation for the device MAC on the actual DHCP server, then create the DNS mapping. If router credentials or UI access are unavailable, do not claim the LAN IP is permanent.

## Tailscale companion naming

Keep Tailscale MagicDNS for remote administration. It is not an internet exposure mechanism: it gives an authenticated encrypted path and stable `<host>.<tailnet>.ts.net` names. A useful dual scheme is:

- LAN: `<host>.home.arpa` via Pi-hole and DHCP reservation.
- Remote: `<host>.<tailnet>.ts.net` via Tailscale MagicDNS.
- Convenience: SSH aliases for local vs remote targets when needed.

Confirm the operating system has SSH/Remote Login enabled before asserting that a discovered Tailscale node is reachable over SSH; an online Tailscale peer can still refuse port 22.
