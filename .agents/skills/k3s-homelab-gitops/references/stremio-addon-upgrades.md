# Stremio add-on upgrades: AIOMetadata and AIOStreams

Use this reference when upgrading the directly managed Stremio add-ons under `apps/aiometadata` or `apps/aiostreams`.

## Discovery and pinning

1. Fast-forward the homelab repo to `origin/main` before editing.
2. Query each upstream GitHub `releases/latest` endpoint for the release tag and notes.
3. Query GHCR directly for the OCI index digest using an anonymous pull token.
4. Never infer that a GitHub release tag is also a container tag:
   - AIOMetadata has historically published releases such as `v2.8.0` while GHCR exposes only `latest`. Pin `latest@sha256:<index-digest>` and annotate the README with the corresponding upstream release.
   - AIOStreams publishes versioned GHCR tags such as `v2.30.6`. Pin `vX.Y.Z@sha256:<index-digest>`.
5. Update both the Deployment image and adjacent README image reference.

Registry check pattern:

```python
import json, urllib.request, urllib.error

repo = "owner/image"
tags = ["vX.Y.Z", "X.Y.Z", "latest"]
token = json.load(urllib.request.urlopen(
    f"https://ghcr.io/token?scope=repository:{repo}:pull&service=ghcr.io",
    timeout=20,
))["token"]

for tag in tags:
    req = urllib.request.Request(
        f"https://ghcr.io/v2/{repo}/manifests/{tag}",
        headers={
            "Authorization": "Bearer " + token,
            "Accept": ", ".join([
                "application/vnd.oci.image.index.v1+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.docker.distribution.manifest.v2+json",
            ]),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            print(tag, response.headers.get("Docker-Content-Digest"))
    except urllib.error.HTTPError as exc:
        print(tag, "missing", exc.code)
```

Use the OCI index digest returned in `Docker-Content-Digest`, not a platform-child digest.

## Validation and deployment

Validate both directories before committing:

```bash
$K apply --dry-run=client -f apps/aiometadata
$K apply --dry-run=client -f apps/aiostreams
git diff --check
git diff -- apps/aiometadata apps/aiostreams
```

Commit and push once, then reconcile in dependency order:

```bash
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization aiometadata --with-source
$F reconcile kustomization aiostreams --with-source
$K -n stremio rollout status deployment/aiometadata --timeout=300s
$K -n stremio rollout status deployment/aiostreams --timeout=300s
```

The two leaf Kustomizations and rollouts may be checked in parallel after the `apps` Kustomization has applied the target Git revision.

## Post-upgrade verification

For each Deployment, verify all of the following rather than stopping at successful rollout:

- Deployment image equals the intended tag and digest.
- Pod `imageID` equals the intended immutable digest.
- Pod is Ready and restart count is zero.
- Flux leaf Kustomization is `Ready=True` at the pushed Git revision.
- Recent application logs contain no startup failure.
- Recent warning events in namespace `stremio` are empty or understood.
- Public routes return HTTP 200:
  - AIOMetadata: `/health` and `/`
  - AIOStreams: `/` and `/stremio/configure`

Application-specific log evidence:

- AIOMetadata should report its version transition and cache cleanup/migration completion, followed by `Server ready to accept requests` and listening on port 3232. Benign invalid mapping entries can occur during mapping imports; distinguish these data-quality notices from startup failures.
- AIOStreams should print the expected release version, complete all database migrations with no pending migrations, initialize its data sources, and report the server running on port 3000.

Do not expose sealed-secret values while inspecting manifests or logs.

## AIOStreams data and configuration pitfalls

- AIOStreams images may not contain `node`, Python, `sqlite3`, `tar`, or `stat`. For a consistent SQLite/PVC backup, briefly scale the Deployment to zero, mount `aiostreams-data` read-only in a temporary Alpine pod, stream a compressed tar archive to a local mode-600 file, verify it with `gzip -t`, remove the pod, and restore one replica. Use a cleanup trap so failures do not leave the application scaled down.
- From AIOStreams 2.31 onward, only bootstrap variables (`BASE_URL`, `SECRET_KEY`, database/auth/log bootstrap settings) must come from the environment. Metadata credentials are runtime settings, preferably managed in the dashboard. Environment variables such as `TMDB_ACCESS_TOKEN`, `TMDB_API_KEY`, `TVDB_API_KEY`, and `TRAKT_CLIENT_ID` are locked overrides.
- Diagnose metadata errors by inspecting Secret **key names** and testing credentials from inside a pod while printing only presence booleans and upstream HTTP status codes. Never print credential values. Do not wire a credential that fails upstream validation.
- Reusing an existing Secret with `env[].valueFrom.secretKeyRef` avoids copying plaintext. Record the cross-Secret dependency and verify the referenced keys exist; a missing key prevents pod startup.
- `TorBox addon is deprecated` usually comes from a persisted user configuration containing a removed preset. It is user data, not a Deployment startup defect. Repair it through the configuration UI rather than mutating encrypted configurations blindly.
- A playback-time `Provider Authentication failure` can likewise be user configuration rather than a Deployment problem. Classify recent logs by add-on label: if a custom add-on such as `StremThru Torz TB` returns HTTP 500 while AIOStreams stays healthy, validate or replace the TorBox API key under the AIOStreams **Services** configuration. Metadata keys (TMDB/TVDB/RPDB) do not authenticate a debrid provider. Verify the repair with a fresh playback attempt and confirm zero provider-auth and add-on-fetch failures in sanitized logs.
- `/api/v1/status` is useful after rollout. Report only bounded fields such as version, tag, channel, `protected`, `tmdbApiAvailable`, and `loggingSensitiveInfo`; the full response may contain instance configuration.
- A tag setter marker on the complete `image:` value conflicts with immutable `tag@sha256:digest` pinning: Flux image automation can replace the entire reference and drop the digest. When immutable pins are required, remove that setter marker and suspend the `ImageUpdateAutomation`; keep the `ImagePolicy` for release visibility and roll out reviewed digest changes manually.