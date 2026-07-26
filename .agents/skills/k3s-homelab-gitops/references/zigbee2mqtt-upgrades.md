# Zigbee2MQTT GitOps upgrades

Use this for this repository's Zigbee2MQTT Deployment at `apps/zigbee2mqtt`, namespace `home-automation`, Deployment `z2m`.

## Safety preflight

1. Sync `$REPO_ROOT` with `origin/main` and require a clean worktree.
2. Verify the running image, Ready state, restart count, recent true log errors/warnings, MQTT publish activity, and Home Assistant state for a known Zigbee entity such as `switch.garden_water`.
3. Never print `/app/data/configuration.yaml`: it can contain MQTT credentials and Zigbee network keys. Inspect only explicitly allowlisted non-secret characteristics. Do not print Kubernetes Secret data.
4. Check whether `/app/data/external_converters` exists and whether `external_converters` is configured. Zigbee2MQTT 2.6.1 changed the external-converter API, especially for Tuya converters. Zigbee2MQTT 2.11 disables external JavaScript by default for new installs; existing installations should still be checked.
5. Compare detected device models, without names or IEEE addresses, against upstream release-note property/model renames.

## Backup

Create a protected local archive without printing its contents:

```bash
BACKUP_DIR=$HOME/backups/zigbee2mqtt
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/zigbee2mqtt-data-pre-<version>-$(date +%Y%m%d-%H%M%S).tar.gz"
$K -n home-automation exec deploy/z2m -- tar -C /app/data -czf - . > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"
gzip -t "$BACKUP_FILE"
stat -c 'path=%n size=%s mode=%a' "$BACKUP_FILE"
sha256sum "$BACKUP_FILE"
```

The archive contains secrets; never list or extract it into agent output.

## Image update

Verify the Docker Hub release tag and OCI index digest, then pin both:

```yaml
image: koenkk/zigbee2mqtt:<version>@sha256:<index-digest>
```

Run both client validation and `git diff --check`; for strategy transitions, also use server-side dry-run.

## USB coordinator rollout pitfall

The coordinator serial device (`/dev/ttyUSB0`) cannot be opened by two pods. A normal RollingUpdate may start the replacement while the old pod still owns the serial lock, causing transient exits with `Resource temporarily unavailable Cannot lock port`.

Keep the Deployment on:

```yaml
strategy:
  type: Recreate
```

Changing an existing Deployment from RollingUpdate to Recreate can fail because the live object retains defaulted `spec.strategy.rollingUpdate`. The declarative manifest cannot always perform both changes atomically through Flux. Transition the live object once:

```bash
$K -n home-automation patch deployment z2m --type=merge \
  -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
```

Then reconcile the Git manifest containing only `type: Recreate`. Verify the live strategy and Flux Ready state. Future upgrades will stop the old pod before starting the new one.

## Reconcile and verify

```bash
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization zigbee2mqtt --with-source
$K -n home-automation rollout status deployment/z2m --timeout=420s
```

Require all of:

- Pod Ready, intended immutable `imageID`, and no increasing restart count.
- Startup log signals show the intended version, MQTT connected, zigbee-herdsman started, and Zigbee2MQTT started.
- Count true log levels using anchored/prefixed patterns such as `] error:` and `] warning:`. Do not count words like `error` appearing inside Home Assistant discovery payload options.
- Continued MQTT publish activity.
- Database, coordinator backup, state, and configuration files still exist; device record count is plausible.
- `https://z2m.erix-homelab.site/` returns HTTP 200.
- A known Home Assistant Zigbee entity remains available.
- Flux `zigbee2mqtt` is Ready at the pushed revision and no cluster pods are unhealthy.
