# Home Assistant GitOps Upgrade Notes

Use this when updating Erik's Home Assistant deployment in the k3s homelab (`apps/home-assistant`, namespace `home-automation`).

## Safe upgrade sequence

1. Sync the homelab repo first:
   ```bash
   cd /home/erix/Projects/homelab
   git fetch origin main && git pull --ff-only origin main
   ```

2. Inspect current cluster state:
   ```bash
   export KUBECONFIG=/home/erix/.kube/config
   K=/home/erix/.local/bin/kubectl
   F=/home/erix/.local/bin/flux
   $F get kustomizations -A | grep -E 'NAME|home-assistant|apps'
   $K -n home-automation get statefulset,deploy,pod,svc,ingress -o wide
   $K get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   ```

3. Check the running Home Assistant version and config before changing the image:
   ```bash
   $K -n home-automation exec homeassistant-0 -c homeassistant -- python -m homeassistant --version
   $K -n home-automation exec homeassistant-0 -c homeassistant -- python -m homeassistant --script check_config --config /config
   ```
   Treat check-config output as baseline: existing warnings/errors may predate the upgrade, but record them so post-upgrade differences are visible.

4. Create a pre-upgrade config backup without printing archive contents, because `/config` can contain secrets:
   ```bash
   BACKUP_DIR=/home/erix/backups/homeassistant
   mkdir -p "$BACKUP_DIR"
   BACKUP_FILE="$BACKUP_DIR/homeassistant-config-pre-upgrade-$(date +%Y%m%d-%H%M%S).tar.gz"
   $K -n home-automation exec homeassistant-0 -c homeassistant -- tar -C /config -czf - . > "$BACKUP_FILE"
   chmod 600 "$BACKUP_FILE"
   du -h "$BACKUP_FILE"
   sha256sum "$BACKUP_FILE"
   ```

5. Discover the latest stable release and verify the container tag exists. Prefer pinning tag plus OCI index digest:
   ```bash
   python3 - <<'PY'
   import json, urllib.request
   req=urllib.request.Request('https://api.github.com/repos/home-assistant/core/releases/latest', headers={'Accept':'application/vnd.github+json','User-Agent':'hermes-agent'})
   with urllib.request.urlopen(req, timeout=30) as r:
       rel=json.load(r)
   print(rel['tag_name'], rel.get('published_at'), rel.get('html_url'))
   PY
   ```
   Query Docker Hub manifest for `homeassistant/home-assistant:<version>` and use the returned `Docker-Content-Digest` in the manifest image reference:
   ```yaml
   image: homeassistant/home-assistant:<version>@sha256:<index-digest>
   ```

6. Validate and commit:
   ```bash
   $K apply --dry-run=client -f apps/home-assistant
   git diff -- apps/home-assistant/ha-deployment.yaml
   git add apps/home-assistant/ha-deployment.yaml
   git commit -m "Update Home Assistant image to <version>"
   git push origin main
   ```

7. Reconcile and verify rollout:
   ```bash
   $F reconcile source git flux-system
   $F reconcile kustomization apps --with-source
   $F reconcile kustomization home-assistant --with-source
   $K -n home-automation rollout status statefulset/homeassistant --timeout=520s
   $K -n home-automation get pod homeassistant-0 -o wide
   $K -n home-automation get pod homeassistant-0 -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.image}{"\t"}{.imageID}{"\tready="}{.ready}{"\trestarts="}{.restartCount}{"\n"}{end}'
   $K -n home-automation exec homeassistant-0 -c homeassistant -- python -m homeassistant --version
   $K -n home-automation exec homeassistant-0 -c homeassistant -- python -m homeassistant --script check_config --config /config
   ```

8. Probe the service locally. A `200` on `/` and `401` on `/api/` without a token are acceptable health signals:
   ```bash
   python3 - <<'PY'
   import urllib.request, urllib.error
   for url in ['http://192.168.11.201:8123/', 'http://192.168.11.21:8123/api/']:
       try:
           r=urllib.request.urlopen(url, timeout=10)
           print(url, r.status, r.getheader('Server'))
       except urllib.error.HTTPError as e:
           print(url, e.code, e.headers.get('Server'))
       except Exception as e:
           print(url, 'ERR', type(e).__name__, str(e))
   PY
   ```

9. Inspect startup logs through a sanitizer. Some custom integrations (notably authentication integrations) can log cookie jars, session tokens, or other credentials inside warning/error messages. **Never print raw Home Assistant logs or broadly grep `warning|error` into agent/chat output.** Capture locally with mode `600`, sanitize credential-like fields before viewing, and delete the temporary file afterward. Prefer reporting `(level, logger, count)` first. Never emit the first message from `alexapy.helpers`; it may serialize an entire cookie jar. If message details are needed, use a strict allowlist of known-safe loggers and redact complete `cookies`, `headers`, authorization, and token structures—not only individual `key=value` fragments. Prefer targeted log queries for known component names and bounded messages that cannot contain authentication payloads. If an unsanitized log accidentally exposes credentials, do not repeat them in summaries and recommend rotating the affected session/credential where appropriate.

## Backup CronJob pitfall

Do not rely only on `CronJob/homeassistant-backup` showing `Complete`. It can complete even when the copy did not create a fresh NAS backup, because the script ignores copy failures and a permission error can be hidden in logs.

Verification pattern:
```bash
$K -n home-automation create job --from=cronjob/homeassistant-backup homeassistant-backup-manual-$(date +%Y%m%d%H%M%S)
$K -n home-automation wait --for=condition=complete job/<job-name> --timeout=180s
$K -n home-automation logs job/<job-name> --tail=80
```
Look for errors like `mkdir: can't create directory '/backups/homeassistant': Permission denied` and verify the backup file timestamps are current. If the manual job was only for testing, delete it afterward to avoid persistent warning events:
```bash
$K -n home-automation delete job <job-name>
```

For upgrades, if the CronJob is not proven healthy, create the local `/home/erix/backups/homeassistant/...tar.gz` pre-upgrade backup instead of proceeding without a known restore point.
