# Pi-hole Helm upgrades

Use this procedure for the Helm-managed Pi-hole release in namespace `default`.

## Current deployment model

- Release: `pihole` in namespace `default`.
- Chart: `mojo2600/pihole`.
- Configuration/database PVC: `pihole-pvc`.
- DNS service: `pihole-dns`, LoadBalancer IP `192.168.11.222`.
- Pi-hole is installed directly with Helm, not by a Flux `Kustomization`. The homelab repo's `apps/pihole/values.yaml` and README document the release, but inspect live Helm values before an upgrade.
- Never print `adminPassword`, generated Secret data, or any other credentials. Save sensitive Helm values only to mode-600 files.

## Preflight

1. Fast-forward `$REPO_ROOT` to `origin/main` and require a clean tree.
2. Inspect the live release and workload:

```bash
$H list -A
$H -n default get values pihole -o json > /tmp/pihole-live-values.json
chmod 600 /tmp/pihole-live-values.json
$K -n default get deploy,pod,svc,pvc -l app=pihole -o wide
```

Sanitize live values before showing any output. The live values can differ from the checked-in file.

3. Review every chart release between current and target. Compare chart defaults and templates; some chart releases only bump `appVersion`, but verify rather than assuming.
4. Query Docker Hub for the target `pihole/pihole` OCI index digest. Pin `image.tag` as `<version>@sha256:<index-digest>`; the chart renders `repository:tag`, and Kubernetes accepts this immutable form.
5. Baseline:
   - `pihole status` says FTL listens on TCP/UDP 53 and blocking is enabled.
   - Public resolution through `@192.168.11.222` works.
   - At least one known `<host>.home.arpa` record and the other expected local records resolve.
   - A known blocked domain returns `0.0.0.0`.
   - TCP DNS works (`dig +tcp`).
   - Cloudflared resolves through `127.0.0.1:5053` inside its sidecar.
   - Web ingress behavior is unchanged (`/admin/` normally redirects; API endpoints may require authentication).

## Protected backup

Create both:

- a mode-600 `helm get values -o json` backup;
- a mode-600 tar.gz of `pihole-pvc` plus a SHA-256 sidecar.

For a consistent SQLite/PVC backup:

1. Set a cleanup trap that deletes the temporary pod and restores one Pi-hole replica.
2. Scale `deployment/pihole` to zero and wait for its pod to disappear.
3. Mount `pihole-pvc` read-only in a temporary Alpine pod.
4. Stream `tar -C /data -czf - .` to `$HOME/backups/pihole/`.
5. Run `gzip -t`, record `sha256sum`, delete the temporary pod, restore one replica, and verify `pihole status`.

## Dry-run and upgrade

Use `Recreate` so two Pi-hole processes never write the same SQLite-backed PVC during a rollout.

```bash
TAG='<version>@sha256:<oci-index-digest>'
$H upgrade pihole mojo2600/pihole \
  -n default \
  --version <chart-version> \
  --reuse-values \
  --set-string "image.tag=$TAG" \
  --set-string strategyType=Recreate \
  --dry-run=server --hide-secret
```

Render to a protected temporary file and server-side dry-run the Kubernetes resources. Parse only the Deployment image/strategy and resource kinds; do not display rendered Secret data.

Deploy atomically:

```bash
$H upgrade pihole mojo2600/pihole \
  -n default \
  --version <chart-version> \
  --reuse-values \
  --set-string "image.tag=$TAG" \
  --set-string strategyType=Recreate \
  --atomic --timeout 10m
```

Update `apps/pihole/values.yaml` and README with the reviewed chart/image versions, immutable digest, and `Recreate`, then render the checked-in values before committing and pushing.

## Verification

Require all of the following:

- Helm release is deployed at the expected chart/app version and revision.
- Deployment is `1/1`, strategy is `Recreate`, and image spec has the expected tag/digest.
- Pod `imageID` matches the intended digest, all containers are Ready, and restart counts are zero.
- `pihole version` reports expected Core/Web/FTL versions.
- `pihole status` is healthy and blocking remains enabled.
- UDP and TCP DNS, public resolution, expected `home.arpa` records, blocking, and Cloudflared DoH all pass.
- `pihole-dns` retains `192.168.11.222` and expected TCP/UDP port 53.
- Web ingress behavior is unchanged.
- Recent logs and warning events are reviewed.
- Git is clean and pushed; reconcile `GitRepository/flux-system` only to ingest the documentation commit. This does not deploy Pi-hole because the release is Helm-managed.

### One-time `antigravity_count` startup error

After upgrading an older v6 gravity database to a release that counts antigravity domains, FTL may log once:

```text
gravityDB_count(... antigravity_count ...) - SQL error step no more rows available
```

Confirm the `info` table lacks `antigravity_count`; do not guess. Run `pihole -g` and capture its output to a protected file because adlist URLs may be private. A successful gravity rebuild inserts both `gravity_count` and `antigravity_count`. Verify both rows with `pihole-FTL sqlite3`, confirm the command had no error lines, and rerun DNS/blocking tests. CAP_SYS_NICE and CAP_SYS_TIME startup warnings are expected when those capabilities are intentionally absent.
