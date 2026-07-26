---
name: k3s-homelab-gitops
description: Use when exploring, troubleshooting, or deploying Erik's k3s homelab via GitHub/Flux GitOps. Documents cluster access, repo layout, Flux image automation, deployment flow, and safe verification commands.
version: 1.0.1
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [k3s, kubernetes, flux, gitops, homelab, github, ghcr]
    related_skills: [github-repo-management, systematic-debugging]
---

# Erik's k3s Homelab GitOps Workflow

## Overview

Erik's homelab is a single-node k3s cluster managed primarily through Flux CD. The source of truth is GitHub, mostly `https://github.com/erix/homelab`, with a few application repos watched directly. Flux reconciles Git manifests into the cluster and Flux image automation updates image tags after GitHub Actions publish new images to GHCR.

Do not print secrets. Kubeconfig, sealed-secret source material, GHCR credentials, Flux auth, and app tokens must remain out of chat/model context.

## When to Use

Use this skill when the user asks about:

- k3s cluster state, workloads, namespaces, ingress, services, storage, or Flux status.
- How a new deployment reaches the cluster from GitHub.
- Adding or troubleshooting an app under `~/Projects/homelab`.
- Flux image automation, ImageRepository/ImagePolicy/ImageUpdateAutomation resources.
- Reconciling deployments manually after Git/GHCR changes.

Do not use for unrelated Kubernetes clusters unless Erik explicitly says it is the same homelab setup.

## Known Environment

This repository-local copy lives under `.agents/skills/k3s-homelab-gitops/` so compatible coding-agent harnesses can discover and reuse it directly.

- Host used for access: `kaiburg` as user `erix`.
- Kubeconfig: `/home/erix/.kube/config`.
- Local kubectl: `/home/erix/.local/bin/kubectl` may exist; if missing, install a matching client locally rather than system-wide.
- Flux CLI: `/home/erix/.local/bin/flux`.
- Helm CLI: `/home/erix/bin/helm`.
- Main repo: `/home/erix/Projects/homelab`, remote `https://github.com/erix/homelab.git`, branch `main`.
- Important caveat: local `~/Projects/homelab` can lag `origin/main`; run `git fetch origin main` before trusting local files. At discovery time cluster and `origin/main` were ahead of local HEAD.

Common shell prefix:

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl
F=/home/erix/.local/bin/flux
H=/home/erix/bin/helm
```

## Current Cluster Shape

Observed on 2026-05-01:

- k3s: Kubernetes `v1.34.4+k3s1`.
- Node: `node-01`, control-plane, IP `192.168.11.21`, Ubuntu 24.04.
- Flux: bootstrapped and healthy, cluster controllers at Flux v2.2.3 component versions.
- Namespaces include: `default`, `flux-system`, `kube-system`, `cert-manager`, `metallb-system`, `home-automation`, `immich`, `plex`, `rdt-client`, `splitbot`, `stremio`, `tailscale`, `tunnel`, `network`.
- Main ingress controller: Traefik service at `192.168.11.200`.
- LoadBalancer IPs are mostly MetalLB addresses in `192.168.11.x`.
- Tailscale operator is installed for service exposure; for whole-homelab remote access, prefer subnet routing via `kaiburg` before annotating every Service. See `references/tailscale-subnet-routing.md`.
- Storage classes: `local-path` default, `local-path-ssd`, `nfs-books-csi`; several static TrueNAS/NFS PVs are used for media/data.
- Helm-managed releases observed: `traefik`, `traefik-crd`, `csi-driver-nfs`, `pihole`, `tailscale-operator`.

## GitOps Topology

Flux bootstraps from `clusters/new/flux-system/gotk-sync.yaml`:

- `GitRepository/flux-system`: `https://github.com/erix/homelab`, branch `main`, interval `1m`.
- `Kustomization/flux-system`: path `./clusters/new`, prune enabled, interval `10m`.
- `clusters/new/apps.yaml`: defines `Kustomization/apps` for path `./clusters/new/apps`.
- `clusters/new/apps/kustomization.yaml`: includes per-app descriptors such as `traefik.yaml`, `immich.yaml`, `plex-new.yaml`, `splitbot.yaml`, `trading-dashboard.yaml`, `subscription-tracker.yaml`, etc.

Most apps have a small Flux descriptor in `clusters/new/apps/<app>.yaml` that points at the actual manifests under `apps/<app>` in the homelab repo:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 10m
  path: ../../apps/my-app
  prune: true
  targetNamespace: default
  sourceRef:
    kind: GitRepository
    name: flux-system
```

Two app repos are watched directly:

- `GitRepository/movie-night`: `https://github.com/erix/movie-night-app`, branch `master`, path `./k8s`.
- `GitRepository/splitbot`: `https://github.com/erix/splitbot`, branch `main`, paths `./k8s/overlays/local` and `./k8s/tunnel/overlays/local`.

## Deployment Flow from GitHub

There are two patterns.

### Pattern A: app repo builds image, homelab repo deploys it

Used by apps such as `trading-dashboard`, `subscription-tracker`, often `splitbot`.

1. Developer pushes app code to the app repo.
2. GitHub Actions builds and pushes an image to GHCR, e.g. `ghcr.io/erix/trading-dashboard:master-26-sha-256ea02` or `ghcr.io/erix/splitbot:main-14-sha-<fullsha>`.
3. Flux `ImageRepository` scans GHCR every 1m/5m/1h depending on app.
4. Flux `ImagePolicy` picks the newest matching tag by numeric run/build or semver.
5. Flux `ImageUpdateAutomation` edits a setter comment in Git and pushes a commit, usually to `erix/homelab:main`:
   ```yaml
   newTag: main-14-sha-... # {"$imagepolicy":"flux-system:splitbot:tag"}
   ```
6. Flux source-controller sees the homelab repo commit.
7. Flux kustomize-controller applies the changed Kustomization to the cluster.

### Pattern B: app repo is a Flux source

Used by `movie-night` and partly `splitbot`.

1. GitHub Actions in the app repo builds/pushes the image.
2. Flux watches the app repo as a `GitRepository`.
3. For `movie-night`, `ImageUpdateAutomation/movie-night` writes directly back to the app repo branch `master`, path `./k8s`.
4. Flux applies the app repo kustomization path directly.

## Current Image Automations

Observed image policies:

- `immich`: `ghcr.io/immich-app/immich-server`, semver tags `vX.Y.Z`, updates `./apps/immich` in homelab. Policy is constrained to `>=3.0.0 <4.0.0`; major upgrades require migration review.
- `immich-ml`: `ghcr.io/immich-app/immich-machine-learning`, aligned to the same `>=3.0.0 <4.0.0` major-version constraint and Immich automation.
- `aiostreams`: `ghcr.io/viren070/aiostreams`, patch-only `v2.30.x` policy (`>=2.30.0 <2.31.0`), updates `./apps/aiostreams`. Advancing to a new minor line is deliberate.
- `plex`: `lscr.io/linuxserver/plex`, alphabetical LinuxServer version tags, updates `./apps/plex-new`.
- `movie-night`: `ghcr.io/erix/movie-night`, tags `build-<run>-sha-<7sha>`, updates app repo `./k8s` on `master`.
- `splitbot`: `ghcr.io/erix/splitbot`, tags `main-<run>-sha-<40sha>`, updates homelab `./clusters/new/apps`.
- `subscription-tracker`: `ghcr.io/erix/subscription-tracker`, tags `main-<run>-sha-<sha>`, updates homelab `./clusters/new/apps`.
- `trading-dashboard`: `ghcr.io/erix/trading-dashboard`, tags `master-<run>-sha-<7sha>`, updates homelab `./clusters/new/apps`.

Some private images use `secretRef: ghcr-credentials`; never print or inspect secret data.

## Safe Exploration Commands

Status:

```bash
$F check --pre=false
$F get sources git -A
$F get kustomizations -A
$F get images repository -A
$F get images policy -A
$F get images update -A

$K get nodes -o wide
$K get ns
$K get deploy,statefulset,daemonset,cronjob -A -o wide
$K get svc -A -o wide
$K get ingress -A
$K get sc,pv,pvc -A
$H list -A
```

Read Flux specs without secrets:

```bash
$K -n flux-system get gitrepositories,kustomizations,imagerepositories,imagepolicies,imageupdateautomations
$K -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io -o json \
  | jq -r '.items[] | [.metadata.name, .spec.sourceRef.name, (.spec.path//""), (.spec.interval//""), (.spec.targetNamespace//""), (.status.conditions[]? | select(.type=="Ready") | .status), (.status.lastAppliedRevision//"")] | @tsv' \
  | sort
```

Warnings and health:

```bash
$K get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
$K get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -40
```

## Add a New Homelab-Managed App

For TrueNAS-backed media web apps, also see `references/truenas-media-webapps.md` for the read-only NFS export + static PV/PVC + nginx media-serving pattern.
For private GitHub/GHCR app repos, see `references/private-ghcr-flux-apps.md` for the trading-dashboard-compatible private image pull + Flux automation pattern. For static HTML/CSS/JS sites that publish automatically from GitHub to private GHCR and then Flux, see `references/static-site-ghcr-flux.md`.
For querying the deployed subscription-tracker API, see `references/subscription-tracker-api.md` for internal access, OpenAPI discovery, and transaction/category query examples.
For Tailscale subnet routing, exit-node pitfalls, and k3s operator exposure strategy, see `references/tailscale-routing.md`. For the special case where Tailscale Serve fronts the local Hermes dashboard on `kaiburg.tail9139a.ts.net`, see `references/tailscale-serve-hermes-dashboard.md` for the 502 → loopback bind → Host-header 400 diagnostic path. For Pi-hole local DNS, DHCP-reservation ordering, `home.arpa`, and Tailscale companion naming, see `references/home-network-naming.md`. For safe use of the existing Home Assistant UniFi integration, verified UniFi API reservation updates, and Helm-managed Pi-hole records, see `references/unifi-dhcp-local-dns.md`.

1. Create manifests in `~/Projects/homelab/apps/<app>/`:
   - `deployment.yaml`, `service.yaml`, optional `ingress.yaml`, optional `pvc.yaml`, `kustomization.yaml`.
   - If private GHCR image, reference `imagePullSecrets: [{ name: ghcr-credentials }]` in the Deployment. **The pull secret must exist in the workload namespace**; if creating a new namespace, copy the existing `default/ghcr-credentials` secret into it without printing secret data.
   - Use sealed secrets for sensitive env; never commit plain Secret manifests.
2. Create `clusters/new/apps/<app>.yaml` with a Flux `Kustomization` pointing to `../../apps/<app>`.
3. Add `- <app>.yaml` to `clusters/new/apps/kustomization.yaml`.
4. If image automation is desired, add `ImageRepository`, `ImagePolicy`, and `ImageUpdateAutomation` to `clusters/new/apps/<app>.yaml`; for private GHCR packages, set `ImageRepository.spec.secretRef.name: ghcr-credentials`. Add a setter marker next to the Kustomization image `newTag`.
5. Commit and push to `origin/main`.
6. Reconcile and verify:
   ```bash
   $F reconcile source git flux-system
   $F reconcile kustomization apps --with-source
   $F reconcile kustomization <app> --with-source
   $F get kustomization <app>
   $K get pods -n <namespace> -l app=<app>
   $K logs -n <namespace> -l app=<app> --tail=80
   ```

## Manual Rollout / Reconcile Recipes

### Home Assistant GitOps upgrades

When updating Home Assistant, use `references/home-assistant-upgrades.md` for the full workflow. Key differences from a generic image bump: run `check_config` before and after the change, create a local pre-upgrade `/config` backup without printing archive contents, pin `homeassistant/home-assistant:<version>` to its Docker Hub OCI index digest, reconcile `home-assistant`, then verify the StatefulSet, reported HA version, HTTP `/` and `/api/` behavior, and post-upgrade config check. Do not assume `CronJob/homeassistant-backup` is healthy merely because recent Jobs are `Complete`; inspect logs and current backup timestamps, because copy failures may be ignored.

### Zigbee2MQTT upgrades

When updating Zigbee2MQTT, use `references/zigbee2mqtt-upgrades.md`. Key requirements: inspect external-converter use and device-model rename exposure without printing configuration secrets, create a protected `/app/data` backup, pin the release by immutable digest, and keep the Deployment on `strategy.type: Recreate` because rolling updates make both pods contend for the single USB coordinator. Verify MQTT activity, the frontend route, a known Home Assistant Zigbee entity, pod/image health, and Flux readiness.

### Pi-hole Helm upgrades

When updating Pi-hole, use `references/pihole-upgrades.md`. Pi-hole is a direct Helm release in namespace `default`, not a Flux leaf Kustomization. Key requirements: review both chart and container release notes, create a protected offline PVC plus Helm-values backup, pin the image by OCI index digest, use `strategyType: Recreate`, deploy with Helm `--atomic`, and verify UDP/TCP DNS, local `home.arpa` records, blocking, Cloudflared DoH, ingress, logs, and image identity. If FTL logs one missing `antigravity_count` row after the upgrade, rebuild gravity with `pihole -g` and verify both count rows rather than dismissing the error.

### Immich v3 VectorChord migration

When Immich server upgrades to `v3.x` and crash-loops with `No vector extension found`, check whether Postgres is still on `tensorchord/pgvecto-rs:pg14-v0.2.0`. Immich v3 dropped pgvecto.rs support and needs the DB container migrated to Immich's VectorChord-capable Postgres image. Use `references/immich-v3-vectorchord.md` for the exact backup-first workflow, manifest patch, Flux reconcile, migration verification, and the follow-up machine-learning URL check.

### Immich remote machine learning

When Immich logs say the machine learning server is unhealthy, or Erik wants to offload ML to another CPU/GPU host, use `references/immich-remote-machine-learning.md`. Key pitfall: a local `immich-machine-learning` Deployment is not a usable fallback unless a `Service/immich-machine-learning` also exists; verify the configured remote URL from both `kaiburg` and inside the `immich-server` pod before editing manifests.

### Unifi MongoDB memory pressure

When k3s memory looks unexpectedly high, sort pods by memory before tuning the node. If `network/mongodb-0` is the outlier, inspect whether the Unifi MongoDB StatefulSet has no memory limit and no WiredTiger cache cap. Use `references/unifi-mongodb-memory.md` for the backup-first workflow that adds `--wiredTigerCacheSizeGB 1` plus a `2Gi` memory limit, reconciles Flux, and verifies both memory drop and Unifi `/status` health.

### Stremio add-on upgrades and apps that publish only `latest` images

For the complete AIOMetadata + AIOStreams upgrade workflow—including release discovery, GHCR tag/digest probing, validation, Flux reconciliation order, migration-log checks, and HTTP verification—use `references/stremio-addon-upgrades.md`.

Some third-party apps (observed with `apps/aiometadata`, upstream `cedya77/aiometadata`) publish GitHub releases such as `v2.8.0` but do **not** publish matching GHCR tags (`v2.8.0`/`2.8.0` can return manifest unknown while `latest` exists). In that case, pin the `latest` tag by immutable digest instead of leaving a floating tag:

```yaml
image: ghcr.io/owner/app:latest@sha256:<index-digest>
```

Verification pattern:

1. Query the upstream latest release via GitHub API for the expected app version.
2. Query GHCR for the `latest` OCI index digest and platform manifests; do not assume the release tag exists as an image tag.
3. Update the manifest and any README image reference to `latest@sha256:<digest>`.
4. Dry-run apply the app directory before committing: `$K apply --dry-run=client -f apps/<app>`.
## Manual Rollout / Reconcile Recipes

### Update a homelab app to an upstream GitHub/GHCR release without Flux image automation

For apps that use an upstream image directly (for example Stremio add-ons under `apps/<app>`), prefer pinning the release tag plus OCI index digest instead of leaving `:latest` floating. Workflow:

```bash
cd /home/erix/Projects/homelab
git fetch origin main && git pull --ff-only origin main

# Discover latest GitHub release.
python3 - <<'PY'
import json, urllib.request
owner_repo='OWNER/REPO'
req=urllib.request.Request(f'https://api.github.com/repos/{owner_repo}/releases/latest', headers={'Accept':'application/vnd.github+json','User-Agent':'hermes-agent'})
with urllib.request.urlopen(req, timeout=20) as r:
    data=json.load(r)
print(data['tag_name'], data.get('published_at'))
PY

# Verify the GHCR tag exists and get its digest. Try both the release tag
# and any documented image tags; some projects only publish :latest.
python3 - <<'PY'
import urllib.request,json
repo='owner/image'
for tag in ['vX.Y.Z','latest']:
    try:
        token=json.load(urllib.request.urlopen(f'https://ghcr.io/token?scope=repository:{repo}:pull&service=ghcr.io', timeout=20))['token']
        req=urllib.request.Request(f'https://ghcr.io/v2/{repo}/manifests/{tag}', headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'})
        with urllib.request.urlopen(req, timeout=20) as r:
            print(tag, r.headers.get('Docker-Content-Digest'))
    except Exception as e:
        print(tag, 'ERR', e)
PY
```

Then update the Deployment image to `ghcr.io/<owner>/<image>:<tag>@sha256:<index-digest>` and update any adjacent README image reference. Validate before commit:

```bash
$K apply --dry-run=client -f apps/<app>
git diff -- apps/<app>
git add apps/<app>/<deployment>.yaml apps/<app>/README.md
git commit -m "Update <app> image"
git push origin main
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization <app> --with-source
$K -n <namespace> rollout status deployment/<app> --timeout=300s
$K -n <namespace> get deploy <app> -o jsonpath='{.spec.template.spec.containers[0].image}{"\\n"}'
$K -n <namespace> get pods -l app=<app> -o jsonpath='{range .items[*]}{.metadata.name}{"\\t"}{.status.containerStatuses[0].imageID}{"\\tready="}{.status.containerStatuses[0].ready}{"\\n"}{end}'
$K -n <namespace> logs deploy/<app> --tail=80
```

Force Flux to pick up latest Git:

```bash
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization <app> --with-source
```

Force an image automation pass:

```bash
$F reconcile image repository <app> -n flux-system
$F reconcile image update <app> -n flux-system
```

Inspect what Flux applied:

```bash
$F get kustomization <app>
$K -n flux-system describe kustomization <app>
$K -n flux-system logs deploy/kustomize-controller --tail=100
$K -n flux-system logs deploy/image-automation-controller --tail=100
```

## Public Static Site Exposure

For the private staging sequence—Pi-hole split DNS, a separate HTTP-only custom-domain Ingress, DNS-provider/TLS compatibility checks, and byte-identical Host-route verification—use `references/custom-domain-staging.md`.

If the user wants exactly one static website public while other homelab services remain private, **do not create a router port-forward to Traefik's shared ports 80/443**. A port-forward exposes the full shared entry point, including every existing ingress hostname that Traefik can route.

Prefer a dedicated Cloudflare Tunnel per public site, routing its explicitly configured hostname directly to that site's `ClusterIP` Service (for example `http://site.site.svc.cluster.local:80`) rather than to Traefik. Keep the site in a dedicated namespace; use a non-root/read-only static-server container, disable service-account token automount, mount no secrets or shared storage, and validate network-policy enforcement before treating it as a lateral-movement boundary. The tunnel must use a separately scoped credential stored as a Secret/SealedSecret, never in Git.

This design has no inbound router ports, no public MetalLB/NodePort/Ingress for the site, and limits the intended internet route to its single configured hostname. See `references/static-site-ghcr-flux.md` for the build-and-deploy side. For the staged LAN-ingress → Namecheap-to-Cloudflare DNS migration → dedicated tunnel workflow, including email-record safeguards, scoped API-token preflight, 1Password/tmux pitfalls, stale 1.1.1 cache purging, post-cutover cleanup, and HTTP-to-HTTPS edge redirection, use `references/public-static-site-cloudflare-tunnel.md`.

When adding a MailerLite newsletter to a static site, use `references/static-site-mailerlite.md` for idempotent API group creation, native-form versus server-side proxy choices, token isolation, dashboard human-verification boundaries, GDPR/double-opt-in requirements, sender-domain DNS safeguards, asset-cache invalidation, controlled subscriber cleanup, and end-to-end verification.

## Tailscale Access Pattern

When the user asks to access homelab services through Tailscale, first distinguish the desired access model before modifying manifests:

1. **Individual Service exposure** for a few selected TCP/Kubernetes Services: add `tailscale.com/expose: "true"` to the Service manifest in GitOps, not just with a live annotation.
2. **Traefik exposure** for many existing web apps through the current ingress layer: expose Traefik or use `IngressClass/tailscale` and verify Host-header routing for `*.erix-homelab.site`.
3. **Host subnet routing** when the user wants the tailnet to behave like the home LAN: advertise the relevant LAN/MetalLB routes from `kaiburg` and have the user approve them in the Tailscale admin console. For Erik's current layout, likely routes are `192.168.1.0/24` and `192.168.11.0/24`.

Preflight checks:

```bash
tailscale debug prefs | jq '{AdvertiseRoutes,AdvertiseExitNode,NoSNAT,NetfilterMode}'
cat /proc/sys/net/ipv4/ip_forward
ip route
getent ahostsv4 hass.erix-homelab.site immich.erix-homelab.site plex.erix-homelab.site paperless.erix-homelab.site
```

See `references/tailscale-access-patterns.md` for full commands and verification recipes.

## Tailscale Subnet Router / Exit Node Checks

When Erik wants broad remote access to homelab services, prefer diagnosing Tailscale subnet routing before adding `tailscale.com/expose` annotations to every Service. The k3s cluster already has the Tailscale operator pattern for selected Services, but LAN-style access to Traefik/MetalLB usually depends on the host `kaiburg` advertising routes.

Useful checks on `kaiburg`:

```bash
# Server-side route advertisement and approval state
tailscale debug prefs | jq '{AdvertiseRoutes,AdvertiseExitNode,RouteAll,ExitNodeID,ExitNodeIP,NoSNAT,NetfilterMode}'
tailscale status --json | jq '.Self | {DNSName,TailscaleIPs,AllowedIPs,PrimaryRoutes,Online}'

# Expected once subnet routes are approved in admin console:
# PrimaryRoutes includes 192.168.1.0/24 and/or 192.168.11.0/24.

# Enable/refresh advertised homelab routes without changing existing service exposure
sudo tailscale set --advertise-routes=192.168.1.0/24,192.168.11.0/24

# Optionally advertise kaiburg as an exit node too; this adds 0.0.0.0/0 and ::/0
# but clients must still explicitly select it.
sudo tailscale set --advertise-exit-node --advertise-routes=192.168.1.0/24,192.168.11.0/24
```

Important distinctions:

- **Subnet router** is enough for `hass.erix-homelab.site -> 192.168.11.200`; an exit node is not required for DNS or LAN routes.
- **Exit node** routes all client internet traffic through `kaiburg` only after admin approval and client selection.
- If `AdvertiseRoutes` is set but `PrimaryRoutes` is null/missing, routes are not approved/active in the Tailscale admin console yet.
- If `PrimaryRoutes` is correct but access still fails, inspect the client: Tailscale app connected, iOS/macOS VPN refreshed, Linux `tailscale set --accept-routes=true`, and no conflicting VPN. `tailscale status --json` on `kaiburg` showing the phone offline plus zero `ts-forward` packet counters means the client is not sending traffic over the route.
- For raw path testing, use `http://192.168.11.200` before testing `https://hass.erix-homelab.site`; if the raw IP fails, DNS is not the blocker.
- Verify existing Traefik path from `kaiburg` after route changes with Host headers to `192.168.11.200`; this confirms MetalLB/Traefik was not disturbed.

## Tailscale Remote Access Notes

For Erik's homelab, do not assume the Tailscale Kubernetes operator is the only/best path. If the goal is "access my services through Tailscale," first distinguish:

- **Per-service exposure**: Kubernetes Service annotation `tailscale.com/expose: "true"` creates a tailnet device per service.
- **Subnet routing**: advertise `192.168.1.0/24` and `192.168.11.0/24` from `kaiburg` so existing Traefik/MetalLB hostnames like `hass.erix-homelab.site -> 192.168.11.200` work without per-Service annotations.
- **Exit node**: routes all client internet traffic; it is not required for DNS or Home Assistant access and can break mobile clients if `kaiburg` lacks IPv6 internet egress.

Use `references/tailscale-subnet-routing.md` for exact commands, health checks, rollback, and iOS/client troubleshooting.

## Common Pitfalls

1. **Local repo behind remote.** Always `git fetch origin main` before reading local manifests. If you need to add commits locally, prefer `git pull --ff-only origin main` before editing so the new work is based on current GitOps state. The cluster follows remote Git, not necessarily local HEAD.
2. **Flux push races.** Multiple image automations can try to push to `main` at the same time. Events may show ref lock errors; they often resolve on the next interval. If `git push origin main` is rejected, fetch/rebase before retrying.
3. **Private GHCR apps need two auth points.** For private app repos/packages, use `secretRef: ghcr-credentials` on `ImageRepository` and `imagePullSecrets: [{name: ghcr-credentials}]` in the workload namespace. The existing `trading-dashboard` app is the model; see `references/private-ghcr-flux-apps.md`.
4. **Wrong tag regex.** If GitHub Actions changes tag format, update the `ImagePolicy.filterTags.pattern` and `extract`.
5. **Upstream release tag may not be an image tag.** Some apps publish GitHub releases like `v2.3.0` but only push a `latest` container tag. Do not assume the release tag exists in GHCR/Docker Hub; query the registry manifest first and pin the working tag to its digest.
6. **Missing setter marker.** Image automation only edits fields annotated with Flux setter comments or supported Kustomize image fields.
7. **Shared setter paths defeat per-app suspension.** Several homelab `ImageUpdateAutomation` resources update `./clusters/new/apps`. Any unsuspended automation scanning that shared path can rewrite every matching image-policy setter there, including an app whose own automation is suspended. For a true rollout hold, remove the target app's setter marker or narrow every automation to a per-app path; then verify both remote Git and live `Kustomization.spec.images` before merging or publishing a new image.
5. **Secret leakage.** Do not dump kubeconfig, Kubernetes Secrets, SealedSecret source values, GHCR tokens, or app env secrets.
6. **Deprecated MetalLB annotations.** Warning events mention `metallb.universe.tf/*`; migrate to newer MetalLB IPAddressPool/L2Advertisement style when touching those services.
8. **Private GHCR images need two credentials paths.** Flux image scanning uses `flux-system/ghcr-credentials` via `ImageRepository.spec.secretRef`; the kubelet pull uses an `imagePullSecrets` entry in the workload namespace. New namespaces will not automatically have the default namespace secret, so copy `default/ghcr-credentials` into the app namespace without dumping secret data.
9. **Tailscale subnet routing is not exit-node routing.** For Erik's homelab, prefer `kaiburg` as a subnet router for `192.168.1.0/24` and `192.168.11.0/24`, with phone/laptop clients connected to Tailscale but **Exit Node = None**. Do not assume an exit node is needed for DNS or access to `*.erix-homelab.site`; those names already resolve to Traefik/MetalLB at `192.168.11.200`. Avoid advertising `kaiburg` as an exit node unless IPv6 internet egress is confirmed working; otherwise iOS clients can lose general internet access. See `references/tailscale-routing.md`.
10. **Ping can mislead for MetalLB/Traefik.** `192.168.11.200` may not answer ICMP even when ports 80/443 work. Test with TCP/HTTP Host-header checks rather than ping before concluding routing is broken.
11. **Flux image automation needs matching pushed tags.** For app repos built by GitHub Actions, publish a stable Flux-sortable tag such as `main-<run_number>-sha-<40-char-sha>` and use a matching `ImagePolicy.filterTags.pattern`. `latest` can work for initial deployment, but automation should pin to immutable tags.
10. **Initial image automation may race with other automations.** If `git push` is rejected or a local commit disappears during rebase, fetch/pull `origin/main`; Flux may already have pushed the desired setter update. Verify the remote manifest before recommitting.
11. **Flux GitRepository auth secret can break if missing or malformed.** `GitRepository/flux-system` and some private app repos may reference `secretRef: flux-system-http-auth`. If Flux reports `authentication required` while local `gh` works, verify only secret metadata/keys (never values). Recreate the secret from `gh auth token` without trailing newlines in `username`/`password` files; newlines caused Flux/go-git auth failures even though the secret existed.

## DNS propagation and post-cutover cleanup

Cloudflare can report a zone Active while recursive resolvers still cache the registrar's old delegation. Check all layers independently:

1. Registry delegation with `dig +trace NS <domain>`.
2. Cloudflare authoritative answers by querying an assigned Cloudflare nameserver directly.
3. Multiple recursive resolvers such as `1.1.1.1` and `8.8.8.8`.
4. Pi-hole's actual DoH/upstream resolver **bypassing** temporary local host overrides. For the current Pi-hole/cloudflared sidecar pattern, query `127.0.0.1:5053` from the Pi-hole pod.

Mixed answers are normal immediately after a nameserver change. Use `dig +noall +answer` to inspect remaining TTLs, but do not wait blindly when the parent registry and authoritative Cloudflare answers are already correct. Cloudflare's official `https://one.one.one.one/purge-cache/` endpoint can purge stale apex NS/A/AAAA and `www` A/AAAA/CNAME entries; then restart the Pi-hole Cloudflared sidecar/Deployment once if its local DoH cache still serves the old answer. See `references/public-static-site-cloudflare-tunnel.md` for the exact remediation and cleanup gate. Do not remove split-DNS overrides while Pi-hole's own upstream still returns the old provider or cannot resolve `www`.

Cloudflare edge certificates for apex and `www` may become available a few minutes apart. Poll both HTTPS hostnames independently and require trusted TLS plus HTTP 200 before cleanup.

Exact public response hashes may differ from the origin because Cloudflare can inject or transform edge content such as email-address obfuscation. Compare apex and `www`, expected title/content markers, status, and origin semantics; do not diagnose a tunnel failure from a hash mismatch alone.

Once the LAN resolver's upstream sees the new Cloudflare delegation and both public names pass HTTPS:

- remove the temporary Pi-hole apex/`www` mappings;
- remove the temporary LAN-only custom-domain Traefik Ingress;
- reconcile Flux and verify the Ingress is pruned;
- confirm LAN clients now traverse Cloudflare and receive the correct certificate;
- retain the dedicated tunnel, target Service, catch-all 404, and connector NetworkPolicy.

Prefer completing post-cutover cleanup inline once provider caches can be purged and verified. If a delayed job is unavoidable, make it safety-gated and require it to report observed gate values even when no changes occur. Independently inspect live Helm, DNS, Kubernetes, Flux, and HTTPS state afterward; never infer success merely because a one-shot job disappeared from the scheduler.

## Verification checklist

- [ ] `flux check --pre=false` passes except acceptable old CLI warning.
- [ ] `GitRepository/flux-system` ready at expected `origin/main` revision.
- [ ] Target `Kustomization` is Ready=True and last applied revision matches expected commit.
- [ ] Target image policy reports the expected latest image tag.
- [ ] No pods are Pending/CrashLoopBackOff for the app namespace.
- [ ] Ingress host and Traefik address are present if the app should be internally reachable through Traefik; public single-site tunnels route directly to the target ClusterIP instead.
- [ ] After a public tunnel cutover, temporary Pi-hole host overrides and temporary LAN-only custom-domain Ingresses are removed only after upstream DNS and HTTPS pass.
- [ ] Recent warning events have been reviewed.
- [ ] Local `~/Projects/homelab` state is not mistaken for remote/cluster state.
