# UniFi DHCP Reservations and Pi-hole Local DNS

Use this for stable LAN hostnames for ordinary DHCP clients on Erik's home network. This is separate from Kubernetes service discovery and should not be used to reconfigure infrastructure that already has statically configured management addresses.

## Scope and current LANs

- **Default LAN**: UniFi network `Default`, gateway/subnet `192.168.1.1/24`, DHCP enabled. This is the LAN for desktop/server clients such as Kaiburg, Macs, and TrueNAS.
- **IoT** (`192.168.3.1/24`) and **Homelab** (`192.168.11.1/24`) are distinct networks; do not apply the Default-LAN DHCP search-domain change to them by accident.
- Pi-hole DNS is exposed at `192.168.11.222` and is installed as Helm release `pihole` in namespace `default`.

## Safe UniFi access via Home Assistant integration

Home Assistant has a UniFi config entry for site `Sonnenhalde`. Its credential is stored in `/config/.storage/core.config_entries` inside the Home Assistant container.

**Never print, deserialize into chat, or copy the username/password out of the pod.** If the user explicitly authorizes use of this existing integration account, run a script *inside* `homeassistant-0` that:

1. Locates the `domain == "unifi"` config entry.
2. Reads its `host`, `port`, `username`, `password`, `site`, and `verify_ssl` only in-process.
3. Logs in using `POST /api/login` (fall back to `/api/auth/login` if necessary).
4. Emits only status codes and non-secret resource fields needed for the task.

The legacy UniFi Network API works with the direct API prefix in this environment:

- List connected clients: `GET /api/s/<site>/stat/sta`
- List network configurations: `GET /api/s/<site>/rest/networkconf`
- Update a client record: `PUT /api/s/<site>/rest/user/<client-_id>`

Use `/proxy/network/api/s/<site>` only as a fallback prefix if the direct endpoint fails.

### Create or confirm a DHCP reservation

1. Find the client by its MAC address from the client list. Confirm its current LAN IP before changing anything.
2. Update only the client object fields below:

```json
{"use_fixedip": true, "fixed_ip": "192.168.1.x"}
```

3. Re-read `GET /rest/user/<client-_id>` and verify both `use_fixedip == true` and the expected `fixed_ip`.

This pattern successfully verified reservations for Kaiburg, Mac Mini, iMac, and TrueNAS. Kaiburg and TrueNAS were already reserved; do not overwrite an existing stable reservation unless the user requests a different address.

## Pi-hole records managed through Helm

Do not edit the running Pi-hole container or ConfigMap by hand. Update the Helm release with `dnsmasq.additionalHostsEntries`:

```yaml
dnsmasq:
  additionalHostsEntries:
    - "192.168.1.100 kaiburg.home.arpa kaiburg"
    - "192.168.1.166 mac-mini.home.arpa mac-mini"
```

Important: Helm list values **replace**, rather than append to, prior arrays. When adding a host, submit the complete existing `additionalHostsEntries` list, not only the new line.

Deployment pattern:

```bash
helm upgrade pihole mojo2600/pihole --version 2.35.0 \
  --namespace default --reuse-values --values /tmp/known-machines-pihole-values.yaml \
  --dry-run --debug

helm upgrade pihole mojo2600/pihole --version 2.35.0 \
  --namespace default --reuse-values --values /tmp/known-machines-pihole-values.yaml \
  --wait --timeout 180s
kubectl -n default rollout status deployment/pihole --timeout=180s
```

Verify DNS directly against the Pi-hole pod before relying on a client resolver, because individual hosts can have a public fallback resolver configured:

```bash
kubectl -n default exec <pihole-pod> -c pihole -- \
  nslookup <host>.home.arpa 127.0.0.1
```

## Search domain rollout

For short LAN commands such as `ssh kaiburg`, inspect the UniFi `Default` network object first, then set the DHCP search/domain field to `home.arpa` using the appropriate field name returned by the controller version. Preserve all unrelated network configuration fields and re-read the object after the update. Clients need a DHCP lease renewal before the search domain takes effect.

Tailscale MagicDNS remains the complementary remote-access path: use short names or `*.tail9139a.ts.net` when away from the LAN. Do not replace subnet routing or make router port forwards as part of this DNS workflow.
