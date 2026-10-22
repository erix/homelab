# Backups to TrueNAS and email alerts

Use this when adding or debugging a backup CronJob, when an alert email arrives, or when adding a workload to alerting.

## TrueNAS backups share

- Server `192.168.1.179`, NFSv4 only. `showmount -e` does not work; to see what is exported, mount `/` read-only from a throwaway pod and list it.
- Backups go to `/mnt/tank/backups`, one folder per job.
- The share's **Maproot User/Group** must be `root`/`wheel`. From 2026-03-08 until 2026-10-22 it was not, so every root job got `Permission denied`. The `homeassistant`, `mariadb` and `z2m` backups silently stopped for those seven months.
- A job that runs as a non-root user needs its folder created on TrueNAS and owned by that user before the first run. The cluster cannot create it.

| Job | Namespace | Defined in | Runs as | Folder | Keeps |
|---|---|---|---|---|---|
| `homeassistant-backup` | `home-automation` | `apps/home-assistant/ha-backup-cronjob.yaml` | root | `homeassistant` | 30 |
| `mariadb-backup` | `home-automation` | `apps/maria-db/mariadb-backup-cronjob.yaml` | root | `mariadb` | 30 |
| `z2m-backup` | `home-automation` | `apps/zigbee2mqtt/z2m-backup-cronjob.yaml` | root | `z2m` | 30 |
| `watchlist-sync-backup` | `watchlist-sync` | `k8s/overlays/local/backup.yaml` in `erix/watchlist-sync` | 10001 | `watchlist-sync` (owned 10001, mode 700) | 14 |

The three home-automation jobs share the PV/PVC `k3s-backups-pv`/`k3s-backups-pvc`, defined in `apps/home-assistant/backups-volume.yaml`.

## Writing a backup job

A job must fail when the backup did not land. `Completed` alone proves nothing: the old jobs reported success for seven months of failed writes.

- Start the script with `set -euo pipefail`. In images where `/bin/sh` is `dash` (e.g. `mariadb`), use `/bin/bash`: dash has no `pipefail`.
- Never end a copy with `|| true`.
- Write to `<file>.partial`, check it (`gzip -t`, or for `mysqldump` the final `Dump completed` line), then `mv` it into place.
- Use `restartPolicy: Never`, `backoffLimit: 2`, `concurrencyPolicy: Forbid`, `failedJobsHistoryLimit: 3`.
- Add the alert annotation below.
- Prove the failure path: run the script once against the share mounted read-only, and expect exit code 1.

## Email alerts

`apps/alerts/` holds a watcher CronJob (`alerts/alerts-watcher`, every 10 minutes). It emails `erik.simko@gmail.com` from `alerts@erix-homelab.site` through `mail-relay.default.svc` (upstream: Amazon SES).

- **CronJobs** opt in with the annotation `alerts.erix-homelab.site/max-age: <window>` (e.g. `26h` for a daily job). The watcher alerts when the latest run failed (the email includes its last 15 log lines), or when no run succeeded within the window.
- **Apps** are added as health URLs in `HEALTH_URLS` in `apps/alerts/cronjob.yaml`. Any status other than 200 is a problem. A JSON body `{"problems": [...]}` is quoted in the email.
- Each problem is emailed once when it opens and once when it clears. Open problems are kept in ConfigMap `alerts/alerts-state`, where `{}` means all clear.
- Mail sent from pods must carry its own `Date` and `Message-ID` headers: neither `smtplib` nor the relay adds them, and Gmail dropped one alert without them.
- Logic tests: `uv run --with pytest python -m pytest apps/alerts/test_watcher.py`.

Who watches the watcher: the owner's Grok bot runs a homelab health routine. Useful signals for it:

```bash
kubectl -n alerts get cronjob alerts-watcher -o jsonpath='{.status.lastSuccessfulTime}'   # expect < ~30 min old
kubectl -n alerts get configmap alerts-state -o jsonpath='{.data.open}'                   # expect {}
```

## watchlist-sync

Trakt/Simkl watchlist and watch-history sync at `https://watchlists.erix-homelab.site`, from `erix/watchlist-sync`. It is deployed via `clusters/new/apps/watchlist-sync.yaml` with image automation. State is one SQLite file on PVC `watchlist-sync-data`.

- `/healthz` answers whether the web server is up (liveness). `/healthz/sync` returns 503 when a login needs renewing, or when two sync intervals plus 10 minutes have passed without a successful sync. It is in `HEALTH_URLS`.
- Restore and backup details are in that repository's README, under "Backups".
