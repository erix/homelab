# Stable Homelab Hostnames: UniFi DHCP + Pi-hole DNS

Use this when Erik wants stable SSH names for ordinary LAN computers without relying on remembered IP addresses.

## Scope and policy

- Use **UniFi DHCP reservations** for user computers and other DHCP clients.
- Use **Pi-hole local DNS** records under `home.arpa` for LAN names.
- Keep **Tailscale MagicDNS** for remote encrypted access; it is complementary, not a replacement for LAN DNS.
- Do **not** change networking for Proxmox, TrueNAS, or k3s control-plane nodes merely for convenience. Those infrastructure hosts should retain explicitly configured static management addresses. Add DNS aliases only if requested.
- Never print Home Assistant's stored UniFi username/password, HTTP cookies, API tokens, or raw API responses.

## Discover the client record

The Home Assistant UniFi integration can provide an existing least-privilege controller account. Its config entry is stored at:

```text
/config/.storage/core.config_entries
```

inside the `homeassistant-0` pod/container in namespace `home-automation`.

1. Parse the config-entry JSON **inside the container** and select `domain == "unifi"`.
2. Use the `host`, `port`, `username`, `password`, `site`, and `verify_ssl` values only in an in-container script. Print only booleans, HTTP status codes, and the selected client’s non-secret identifiers.
3. Authenticate with `POST /api/login`; if needed, fall back to `POST /api/auth/login`.
4. Query clients through the first working endpoint:
   - `/api/s/<site>/stat/sta`
   - `/proxy/network/api/s/<site>/stat/sta`
5. Match the intended client by MAC address, not by friendly name; names can be duplicated or stale.

## Create and verify a reservation

For a matched client object `_id`, make the idempotent update through the same working API prefix:

```http
PUT <prefix>/rest/user/<_id>
Content-Type: application/json

{"use_fixedip": true, "fixed_ip": "<reserved-ip>"}
```

Then fetch `GET <prefix>/rest/user/<_id>` and verify both:

```text
use_fixedip == true
fixed_ip == <reserved-ip>
```

A `200` on the update alone is insufficient; always read back the record.

## Add Pi-hole DNS records with Helm

Pi-hole is Helm release `pihole` in namespace `default`, chart `mojo2600/pihole`. Its DHCP mode may be disabled even when its DNS service is active, so do not attempt to create DHCP reservations through Pi-hole unless `pihole-FTL --config dhcp.active` confirms it.

Create a values overlay like:

```yaml
dnsmasq:
  additionalHostsEntries:
    - "192.168.1.100 kaiburg.home.arpa kaiburg"
    - "192.168.1.166 mac-mini.home.arpa mac-mini"
    - "192.168.1.212 imac.home.arpa imac"
```

Apply conservatively:

```bash
helm upgrade pihole mojo2600/pihole --version 2.35.0 --namespace default \
  --reuse-values --values /path/to/hostnames.yaml --dry-run --debug

helm upgrade pihole mojo2600/pihole --version 2.35.0 --namespace default \
  --reuse-values --values /path/to/hostnames.yaml --wait --timeout 180s
```

### Critical pitfall: arrays replace, they do not merge

`dnsmasq.additionalHostsEntries` is an array. Every Helm overlay must include **all existing desired hostname entries**, otherwise a new one replaces the prior list.

Verify after the Pi-hole rollout from its own resolver, avoiding ambiguous host-level fallback DNS:

```bash
kubectl -n default exec <pihole-pod> -c pihole -- \
  nslookup <hostname>.home.arpa 127.0.0.1
```

## SSH follow-up

DNS does not enable macOS SSH. On the Mac, enable **System Settings → General → Sharing → Remote Login** and restrict login to the intended user(s). Then use:

```bash
ssh <user>@<hostname>.home.arpa       # LAN
ssh <user>@<hostname>.tailnet.ts.net  # remote via Tailscale
```
