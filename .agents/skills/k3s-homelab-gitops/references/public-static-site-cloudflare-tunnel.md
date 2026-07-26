# Public static site via Cloudflare Tunnel

Use this when one website in Erik's k3s cluster must become public while the shared Traefik ingress and all other homelab services remain private.

## Target architecture

```text
visitor -> Cloudflare HTTPS edge -> dedicated outbound cloudflared tunnel
        -> site ClusterIP Service:80
```

Do not port-forward router TCP 80/443 to Traefik. A shared Traefik entrypoint can route every configured ingress hostname and therefore widens the public attack surface far beyond the intended site.

## Staged rollout

### Stage 1: private/LAN hostnames

1. Keep the existing internal hostname and TLS route unchanged.
2. Add the new apex and `www` hosts as a separate Traefik Ingress on the LAN-only `web` entrypoint.
3. Add Pi-hole split-DNS overrides pointing both public names to Traefik's LAN address.
4. Verify each hostname returns HTTP 200 and compare the response body hash with the existing site.
5. Do not claim custom-domain HTTPS is ready unless a certificate valid for those exact names exists.

A separate HTTP-only Ingress is preferable to attaching foreign domains to an existing wildcard TLS secret: a certificate for `*.erix-homelab.site` cannot validate `example.com`.

### Stage 2: public exposure

1. Create one dedicated Cloudflare Tunnel for the site.
2. Route tunnel public hostnames directly to the site Service, e.g. `http://site.default.svc.cluster.local:80`, not to Traefik, and end with a catch-all `http_status:404` rule.
3. Deploy `cloudflared` in a dedicated namespace with no service-account token, no mounted app secrets, a non-root/read-only container, dropped capabilities, a pinned image digest, minimal resources, and a dedicated tunnel credential in a Kubernetes Secret/SealedSecret. Prefer `--token-file` over expanding the token into process arguments.
4. Add restrictive NetworkPolicies where enforcement has been verified. At minimum, permit connector DNS, outbound Cloudflare tunnel traffic, and the target Service only. When forcing HTTP/2, outbound TCP 7844 is sufficient for the tunnel path.
5. Verify Cloudflare reports the tunnel healthy with active connections and both public hostname CNAMEs are proxied to `{tunnel_id}.cfargotunnel.com`.
6. After authoritative nameservers become active and public HTTPS passes, remove temporary Pi-hole overrides unless an intentional internal TLS design exists; otherwise LAN users bypass Cloudflare and receive the wrong Traefik certificate.
7. Confirm unrelated ingress hosts are unreachable through the tunnel.

## Namecheap registrar / Cloudflare DNS migration

The domain may stay registered and renewed at Namecheap while authoritative DNS moves to Cloudflare. On Cloudflare's normal/free full-zone setup, change the domain's nameservers at Namecheap to the two Cloudflare-assigned nameservers; a simple external-DNS CNAME is not a substitute for a full Cloudflare zone unless the account supports partial/CNAME setup.

Before changing nameservers:

- Export or inventory the complete Namecheap zone.
- Preserve MX, SPF, DKIM selectors, DMARC, MailerSend/provider verification TXT records, `mail`, `autodiscover`, CAA, and any unrelated subdomains.
- Keep mail-related records DNS-only, never proxied.
- Compare Cloudflare's automatic import with Namecheap manually; scans can miss selectors and verification records.
- Do not point the apex or `www` at the home public IP.

### DNS API migration pitfalls

A zone created through `POST /zones` may start with **zero imported DNS records** even though the dashboard flow normally offers a scan. Treat API-created zones as empty until verified. DNS queries cannot enumerate every possible owner name, so use Namecheap Advanced DNS, an export, or its API as the authoritative inventory before cutover.

An apex can legitimately have several records with the same owner name: MX, TXT, and a flattened tunnel CNAME. Never build an update map keyed only by `record.name`; updating the apex entry may silently replace an MX or SPF record. Identify records by at least `(type, name, content)` and include MX priority where applicable. After adding the tunnel CNAME, recount and revalidate all email records.

After Cloudflare reports the zone Active, create tunnel hostname routes. Cloudflare terminates browser-facing HTTPS; the encrypted tunnel carries traffic to `cloudflared`, so the internal Service can remain HTTP inside k3s.

## Cloudflare API token

Use a dedicated API token, not the Global API Key. Typical permissions:

- Account: Cloudflare Tunnel — Edit
- Zone: Zone — Edit
- Zone: DNS — Edit
- Zone: Zone Settings — Read for inspection, **Edit** when changing edge settings such as `Always Use HTTPS`
- Optional Zone: Rulesets — Edit, only if creating an edge redirect such as `www` -> apex

Creating a zone that does not yet exist may require initial account/all-zone scope. After creation, rotate to a token restricted to that one zone.

Store the token in 1Password and inject it with `op run`; never print it, put it in command output, Git, a manifest, or chat. Token verification depends on how it was created:

```text
User-owned token:    GET /client/v4/user/tokens/verify
Account-owned token: GET /client/v4/accounts/{account_id}/tokens/verify
```

An account-owned token can legitimately return HTTP 401 from the user-token endpoint while succeeding at the account-token endpoint and on authorized zone API calls. Do not reject it based only on token length or the user-token check. After the appropriate verification, perform a read-only zone lookup before creating anything.

### 1Password preflight pitfalls

- Inspect item titles and field labels only; never field values.
- Consume the token by field ID or `op://` reference to avoid ambiguity from spaces/typos in labels.
- A custom `API Token` field may accidentally be a visible string field; prefer a concealed/password field.
- If the user-token verification endpoint returns HTTP 401, determine whether this is an account-owned token and try `/accounts/{account_id}/tokens/verify` before declaring it invalid. If both the correct verification endpoint and a read-only API call fail, stop before writes and ask the user to check the stored raw token. Do not try to infer or repair a malformed secret.
- If needed, report only non-secret diagnostics such as whether the field is populated, its length, whether it contains whitespace, and whether it uses a safe token character set.

Run all `op` commands in a fresh tmux session. For completion detection, have the tmux script write a separate `.done` file after writing a sanitized log. Do not scan the visible command line for a sentinel string, because the sentinel appears in the command itself and can cause a false early completion.

## HTTP to HTTPS redirection

After trusted certificates for apex and `www` are active, enable Cloudflare's edge redirect rather than adding another public origin path:

```text
PATCH /client/v4/zones/{zone_id}/settings/always_use_https
{"value":"on"}
```

Verify the setting with GET, then test both apex and `www` over plain HTTP. Require a 301/302 redirect to the same HTTPS hostname while preserving path and query string, followed by HTTPS 200.

A token can successfully read `always_use_https` yet receive HTTP 403 on PATCH. This proves Zone Settings Read is present but the write permission is absent or not effective. Do not keep retrying or infer permission from broader `Zone: Edit`; require explicit `Zone -> Zone Settings -> Edit`. A screenshot showing the permission checkbox selected is not proof that the policy was committed: the user must complete the final **Continue / Update / Save token** action, and the PATCH itself is the authoritative permission test. If the API still denies the change after the token policy is saved, the simplest safe fallback is for the user to enable **SSL/TLS -> Edge Certificates -> Always Use HTTPS** in the Cloudflare dashboard, then verify externally. Do not implement an origin redirect unless Cloudflare edge control is intentionally unavailable.

## DNS propagation and post-cutover cleanup

Cloudflare can report a zone Active while recursive resolvers still cache the registrar's old delegation. Check all layers independently:

1. Registry delegation with `dig +trace NS <domain>`.
2. Cloudflare authoritative answers by querying an assigned Cloudflare nameserver directly.
3. Multiple recursive resolvers such as `1.1.1.1` and `8.8.8.8`.
4. Pi-hole's actual DoH/upstream resolver **bypassing** temporary local host overrides. For the current Pi-hole/cloudflared sidecar pattern, query `127.0.0.1:5053` from the Pi-hole pod.

Mixed answers are normal immediately after a nameserver change. Use `dig +noall +answer` to inspect the remaining TTL on stale NS/A answers rather than treating propagation as stuck. Do not remove split-DNS overrides while Pi-hole's own upstream still returns the old provider or cannot resolve `www`.

### Cloudflare 1.1.1.1 stale-cache remediation

If the parent registry delegation and Cloudflare authoritative nameservers are correct but `1.1.1.1` keeps returning the old registrar delegation/address, do not wait blindly or repeatedly schedule cleanup. Cloudflare provides an official purge page at `https://one.one.one.one/purge-cache/`; its request endpoint is:

```bash
curl -sS -X POST \
  "https://one.one.one.one/api/v1/purge?domain=<name>&type=<TYPE>"
```

For a nameserver migration, purge as applicable:

- apex: NS, A, AAAA
- `www`: A, AAAA, CNAME

Wait several seconds, then query `1.1.1.1` again. If Pi-hole's Cloudflared DoH sidecar still serves its own cached answer, restart the Pi-hole Deployment once and query the sidecar directly on port 5053 before removing the split-DNS records.

Cloudflare edge certificates for apex and `www` may become available a few minutes apart. Poll both HTTPS hostnames independently and require trusted TLS plus HTTP 200 before cleanup.

Exact public response hashes may differ from the origin because Cloudflare can inject or transform edge content such as email-address obfuscation. Compare apex and `www`, expected title/content markers, status, and origin semantics; do not diagnose a tunnel failure from a hash mismatch alone.

Once the LAN resolver's upstream sees the new Cloudflare delegation and both public names pass HTTPS:

- remove the temporary Pi-hole apex/`www` mappings;
- remove the temporary LAN-only custom-domain Traefik Ingress;
- reconcile Flux and verify the Ingress is pruned;
- confirm LAN clients now traverse Cloudflare and receive the correct certificate;
- retain the dedicated tunnel, target Service, catch-all 404, and connector NetworkPolicy.

Prefer completing cleanup inline once the provider cache can be purged and verified. If a delayed safety-gated job is truly necessary, make its prompt self-contained and require it to report the observed NS/A/HTTPS gate values even when it makes no changes. Afterward, inspect Helm values, DNS answers, Kubernetes resources, Flux state, and HTTPS directly. Never infer success merely because a one-shot job disappeared from the scheduler.

## Verification checklist

- [ ] GitOps source and app Kustomization are Ready at the intended revision.
- [ ] Custom LAN hosts route to the same Service and response-body hashes match the original site.
- [ ] Pi-hole resolves both names to the intended LAN address.
- [ ] Public authoritative nameservers are Cloudflare and all mail records survived migration.
- [ ] Tunnel routes target only the site ClusterIP Service.
- [ ] Public apex and `www` return trusted HTTPS.
- [ ] No router port-forward to shared Traefik exists.
- [ ] Other homelab ingress hostnames are not exposed through the tunnel.
