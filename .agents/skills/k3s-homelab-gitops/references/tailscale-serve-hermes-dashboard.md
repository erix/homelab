# Tailscale Serve + Hermes Dashboard on kaiburg

Use this when `https://kaiburg.tail9139a.ts.net` or another Tailscale Serve URL points at a local Hermes dashboard.

## Symptom sequence

- `tailscale serve status` shows the base Tailscale HTTPS URL proxying to the Hermes dashboard, commonly:
  ```text
  https://kaiburg.tail9139a.ts.net
  |-- / proxy http://127.0.0.1:18789
  ```
- Browser or `curl -I https://kaiburg.tail9139a.ts.net` returns `502`.
- The local backend probe fails:
  ```bash
  curl -kIs http://127.0.0.1:18789
  ```
- `journalctl --user -u hermes-dashboard.service` contains:
  ```text
  Refusing to bind dashboard to 0.0.0.0 — the auth gate engages on non-loopback binds, but no auth providers are registered.
  There is no unauthenticated public-bind option — to keep it local, bind 127.0.0.1 and tunnel in (SSH / Tailscale).
  ```

## Cause

Hermes dashboard hardening rejects unauthenticated non-loopback binds. A user service like this will crash-loop:

```ini
ExecStart=... hermes_cli.main dashboard --host 0.0.0.0 --port 18789 --no-open --insecure --tui
```

`--insecure` is deprecated/no-op for bypassing auth on public binds. Non-loopback dashboard exposure needs an auth provider; unauthenticated use must stay on loopback.

## Fix the 502 backend-down state

Patch the user systemd unit to bind loopback only:

```ini
ExecStart=... hermes_cli.main dashboard --host 127.0.0.1 --port 18789 --no-open --insecure --tui
```

Then reload/restart outside any process that would be killed by restarting the current gateway/service:

```bash
systemctl --user daemon-reload
systemctl --user restart hermes-dashboard.service
systemctl --user status hermes-dashboard.service --no-pager --lines=40
curl -kIs http://127.0.0.1:18789
```

If operating from inside Hermes/gateway and restart is blocked, `daemon-reload` plus the service's auto-restart may be enough if it is already crash-looping.

## Expected follow-up failure: Host header 400

After binding to `127.0.0.1`, Tailscale Serve may reach the backend but Hermes can reject the browser request:

```json
{"detail":"Invalid Host header. Dashboard requests must use the hostname the server was bound to."}
```

This is DNS-rebinding protection: the app is bound to `127.0.0.1`, while the browser sends `Host: kaiburg.tail9139a.ts.net`.

## Safe resolution options

Choose one deliberately:

1. Use a true local/tunneled URL:
   ```bash
   ssh -L 18789:127.0.0.1:18789 kaiburg
   # open http://127.0.0.1:18789 locally
   ```
2. Configure Hermes dashboard auth (basic auth or OAuth), then expose/bind non-loopback as supported by current Hermes docs.
3. Add/upgrade to a Hermes-supported trusted reverse-proxy hostname feature if available; avoid ad-hoc disabling of Host-header checks.

Do not record this as "Tailscale is broken". DNS and Tailscale can be healthy while the Serve backend is down or Hermes rejects the forwarded Host header.