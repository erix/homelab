# Mail Relay (Send-Only SMTP)

Lightweight SMTP relay for cluster workloads that only need to send outbound
email. The deployment wraps the maintained
[`boky/postfix`](https://github.com/bokysan/docker-postfix) image so that mail
is accepted from in-cluster clients and forwarded through any external SMTP
provider (Mailgun, SendGrid, SES, Mailjet, etc.).

## What You Get
- Authenticated relay through your upstream provider with STARTTLS and SASL.
- Cluster-internal SMTP endpoint (`mail-relay.default.svc:25` or `:587`).
- Locked down to Kubernetes pod CIDRs + homelab LAN via `MYNETWORKS`.
- No inbound delivery, POP/IMAP, or mailbox management — pure send-only.

## Prerequisites
1. Credentials from an upstream provider that permits relaying (user + API key).
2. SPF/DKIM/DMARC records that authorize that provider to send for your domain.
3. `sealed-secrets` CLI access (`kubeseal`) to store credentials in Git.

## Create the Relay Secret
Copy the template, edit values, then seal it before committing:

```bash
cd k3s/apps
cp apps/mail-relay/mail-relay-secret.example.yaml \
   apps/mail-relay/mail-relay-secret.yaml

# Edit mail-relay-secret.yaml with the provider-specific values, then:
kubeseal -f apps/mail-relay/mail-relay-secret.yaml \
  -w apps/mail-relay/mail-relay-secret-sealed.yaml

# Remove the cleartext file once sealed
rm apps/mail-relay/mail-relay-secret.yaml
```

Key fields:
- `RELAYHOST`: `[smtp.provider.com]:587`
- `RELAYHOST_USERNAME` / `RELAYHOST_PASSWORD`: login/API key
- `ALLOWED_SENDER_DOMAINS`: space separated list of domains that can be used in
  the `MAIL FROM` command (prevents abuse)
- Optional DKIM material (`DKIM_SELECTOR`, `DKIM_KEY`) if your provider expects
  you to sign mail yourself rather than via their platform.
- Optional `SMTPD_SASL_USERS`: comma-separated `user:password` pairs that are
  allowed to run SMTP AUTH against the relay. This is handy for workflows (like
  n8n) that require credentials even on trusted networks.

## Deploy

```bash
cd k3s
kubectl apply -f apps/mail-relay/
```

This creates:
- `Deployment/mail-relay` (single replica, stateless)
- `Service/mail-relay` (ClusterIP, ports 25 + 587)
- `SealedSecret` with the relay credentials (after you add it)

## Using the Relay
Point applications at `mail-relay.default.svc.cluster.local:25` (plain) or
`:587` (submission/STARTTLS). Authentication is optional:
- If `SMTPD_SASL_USERS` is empty, the relay simply accepts mail from pod/LAN
  CIDRs listed in `MYNETWORKS`.
- If you populate `SMTPD_SASL_USERS`, clients can authenticate with those
  credentials via SMTP AUTH (LOGIN/PLAIN) and you can hand the same username/
  password to tools such as the n8n Send Email node.

## DNS and Deliverability
- Keep your SPF record pointing at the upstream provider, not this relay.
- Publish DKIM keys according to your provider’s instructions (or use theirs).
- Add/adjust DMARC (`_dmarc.<domain>`) if you haven’t already.

## Monitoring & Maintenance
- Mail logs are available via `kubectl logs deploy/mail-relay`.
- Consider adding a `ServiceMonitor` to collect Postfix metrics if needed.
- Rotate upstream credentials regularly and reseal the secret.
