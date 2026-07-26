# MailerLite integration for static sites

Use this when a static HTML/CSS/JS site on k3s needs a newsletter list or signup form.

## Security boundary

Never put a MailerLite API token in static HTML or browser JavaScript. Keep it in 1Password and inject it only into a server-side setup command with `op run`, or store it as a Kubernetes Secret/SealedSecret for a server-side subscription proxy. Never print token values, Secret data, subscriber addresses, or full API responses containing PII.

For one-off administration, create a 1Password API-credential item and inject it with an op reference such as:

```text
ML_API_TOKEN=op://<vault>/<item>/credential
```

Run all `op` commands inside a fresh tmux session per the 1Password skill.

## API preflight and group creation

MailerLite's current API base is:

```text
https://connect.mailerlite.com/api
```

Use `Authorization: Bearer $ML_API_TOKEN` and `Accept: application/json`.

Before creating anything, list groups and search for an exact name:

```http
GET /api/groups?filter[name]=Hello%20Confidence%20Newsletter&limit=100
```

Create only when no exact match exists:

```http
POST /api/groups
Content-Type: application/json

{"name":"Hello Confidence Newsletter"}
```

Expect `201 Created`, then perform a second filtered GET and require exactly one exact-name result. This makes retries idempotent and avoids duplicate groups.

Do not enumerate or print subscribers merely to verify a group. Group ID, name, and aggregate active count are sufficient.

## Forms API caveat

Re-check the official MailerLite developer documentation before relying on form endpoints. In the API observed in July 2026:

- list forms with `GET /api/forms/{type}` where type is `popup`, `embedded`, or `promotion`;
- `GET /api/forms` without a type returns `405`;
- documented operations list, fetch, update, delete, and list a form's subscribers;
- public documentation did not document creating a form through the API.

An empty `POST /api/forms` may expose validation fields such as `name` and `groups`, but that does **not** make form creation a supported contract. A seemingly valid `name` + `groups` request returned a server error in testing. Do not keep probing payload variants or build production automation on this undocumented route.

Therefore, do not guess an undocumented form-creation payload. Prefer one of these architectures:

1. **MailerLite native embedded form:** create it in the dashboard, attach it to the intended group, enable double opt-in, then embed the generated snippet. This keeps the API token out of the site.
2. **Server-side subscription proxy on k3s:** build a small endpoint that validates email/consent, rate-limits requests, and calls MailerLite with a Secret-mounted token. The static site posts to that endpoint. This is appropriate when form UX must be fully custom.

For a dedicated Cloudflare Tunnel, route only the exact signup path (for example `^/api/newsletter/?$`) to the proxy before the catch-all hostname rule that serves the static site. Restrict the proxy's ingress to the dedicated tunnel pod, allow only DNS plus outbound HTTPS, disable service-account token automount, run non-root/read-only, and keep the MailerLite Secret external to Git/Flux inventory. Test health, invalid email, missing consent, disallowed Origin, honeypot, and rate-limit paths before allowing a real subscription.

MailerLite `POST /api/subscribers` supports `groups`, `status`, `subscribed_at`, `ip_address`, `opted_in_at`, and `optin_ip`. Setting `status: active` with explicit consent metadata is **single opt-in**, not double opt-in. Never describe it as double opt-in. If true double opt-in is required, use a dashboard-created MailerLite form/landing page and verify that a test subscriber is initially `unconfirmed` and becomes `active` only after confirmation.

For headless dashboard login, MailerLite may present a Cloudflare human-verification challenge. Do not bypass it. Ask the user to complete the dashboard-only action or create an API token, then continue through supported API endpoints.

## GDPR and double opt-in

For EU-facing sites:

- use explicit newsletter consent; do not bundle it with unrelated consent;
- state what will be sent and identify the sender;
- link the privacy policy near the submit button;
- avoid pre-checked consent boxes;
- enable double opt-in before accepting real subscriptions;
- retain only fields that are actually needed—email alone is often enough;
- verify unsubscribe behavior before launch.

Do not submit a real person's address as a test without permission. Use an address controlled by the user and delete/unsubscribe it afterward if requested.

## Sending-domain authentication

Sender/domain authentication is separate from creating a group. Retrieve the exact DKIM/SPF/tracking records from the MailerLite dashboard; never invent them. Compare them against existing MX/SPF/DKIM records before editing Cloudflare DNS, because SPF must normally remain a single combined TXT policy rather than multiple competing SPF records.

### Exact-value discipline for account-specific records

Treat domain-verification tokens as byte-exact data. Do **not** trust a single visual transcription from a screenshot: monospace glyphs such as `3`/`5`, `0`/`O`, and `1`/`l` are easy to misread while the resulting DNS record still looks plausible. Prefer the dashboard's **Copy** button and a user-provided text value. If only an image is available, crop and enlarge the value, transcribe it independently twice, and compare the two strings before changing DNS.

If DKIM and SPF turn green but MailerLite still rejects the domain-verification TXT while public DNS appears healthy, do not keep waiting blindly. First compare the dashboard value and the published TXT character-for-character. A one-character token mismatch is more likely than propagation once the same answer is visible from the authoritative nameserver and several recursive resolvers.

Cloudflare's DNS API may return TXT `content` with literal surrounding quotes even when the record was submitted without them. For idempotent API comparisons, normalize only one outer quote pair before matching; do not accidentally publish nested quotes or duplicate verification records. When correcting a token, update the existing MailerLite verification TXT in place and verify exactly one current `mailerlite-domain-verification=` record remains.

After DNS changes:

1. Query an assigned authoritative Cloudflare nameserver directly.
2. Query multiple recursive resolvers such as `1.1.1.1`, `8.8.8.8`, and `9.9.9.9`.
3. Verify DKIM CNAME, the single combined SPF policy, and the exact domain-verification TXT.
4. In MailerLite, click the bottom **Check records** button next to **Restart authentication**; do not restart authentication unless the dashboard generated a genuinely new token.
5. Require MailerLite itself to show the sending domain as authenticated. DNS presence alone is not final proof.

## End-to-end verification

Do not treat a success label as proof of subscription. Inspect the live form action and submit handler first: static templates sometimes prevent the submit event and merely change the button to “You’re on the list,” while MailerLite receives nothing. Record MailerLite aggregate counts before and after a controlled address, exercise the form in a real browser, then query the target group again. Also distinguish a resource-request form that posts to FormSubmit/email from newsletter consent; preserve the requested resource flow and add an optional, unselected newsletter-consent control rather than silently subscribing guide requesters.

### Static-asset cache trap

After deploying new HTML and JavaScript, the live HTML can contain the new form while a browser or CDN still serves the old submit handler. A success-looking button with no new MailerLite subscriber is a strong signal for stale JavaScript, not a working integration. Fingerprint or version modified assets in HTML (for example `script.js?v=<release>` and the corresponding modified CSS), deploy the new image, open a fresh browser context, and verify the visible status plus the MailerLite API result. Do not rely only on a DOM success message.

### Controlled subscriber test and cleanup

Use a unique synthetic address that does not belong to a real person, then verify the subscriber directly by email or ID. Require the expected status, target group membership, `opted_in_at`, and `optin_ip` before calling the test successful. Delete the synthetic subscriber afterward and query the subscriber list directly to confirm it is absent. MailerLite group aggregate counters can lag behind subscriber deletion, so a stale `active` count is not proof that cleanup failed.

For a guide form that must continue to a separate provider such as FormSubmit, call the newsletter endpoint only when the optional checkbox is selected, then hand off to the native form submission regardless of newsletter API failure. In a browser test, suppress the external guide delivery while preserving this control flow—for example by temporarily replacing `HTMLFormElement.prototype.submit` with a marker function—then assert that the newsletter call completed and the native handoff was attempted.

- exact subscriber group exists once;
- form is attached to that group;
- token is absent from generated HTML, JS bundles, Git, Flux manifests, and logs;
- invalid email and missing-consent submissions are rejected;
- valid test submission creates an unconfirmed subscriber when double opt-in is enabled;
- confirmation promotes the subscriber to active;
- single-opt-in proxy tests instead require active status plus consent timestamp/IP and must be described explicitly as single opt-in;
- welcome/confirmation links use public HTTPS;
- unsubscribe works;
- sender domain shows authenticated in MailerLite;
- public site remains functional with JavaScript errors/network failures handled visibly.
