# TrueNAS-backed media web apps on Erik's k3s

Session-derived pattern from creating a meditation web player backed by TrueNAS media.

## When to use

Use this when building a small web app that serves media already stored on TrueNAS and should run in Erik's k3s cluster.

## Proven pattern

1. Put the media in its own TrueNAS dataset when possible, e.g. `tank/meditations` mounted at `/mnt/tank/meditations`.
2. Keep SMB for human/macOS access, but add a **read-only NFS export** for k3s:
   - Path: dataset mountpoint, e.g. `/mnt/tank/meditations`
   - Networks: `192.168.11.0/24`
   - `ro: true`
   - Enable/reload NFS after creating the export.
3. In k3s, use a static `PersistentVolume` with `ReadOnlyMany` and `nfsvers=4.1`, then a PVC bound by `volumeName`.
4. Mount the PVC read-only into the web container at the path the app uses for media URLs.
5. Serve media via nginx with explicit MIME types and `Accept-Ranges` so browser audio seeking works.

6. If the image is published from a private app repo/private GHCR package, use the same pattern as `trading-dashboard`:
   - GitHub Actions publishes both `latest` and an immutable Flux tag, e.g. `main-${{ github.run_number }}-sha-${{ github.sha }}`.
   - Deployment has `imagePullSecrets: [{ name: ghcr-credentials }]`.
   - The app namespace has its own `ghcr-credentials` secret copied from `default` or created by sealed-secret flow; do not print the secret.
   - Flux `ImageRepository` in `flux-system` has `secretRef.name: ghcr-credentials` and `ImagePolicy` matches the immutable tag pattern.

## Dr Joe shop metadata for meditation covers/titles

For the meditation-player session, product titles/covers were fetched from the Next.js app's backend API rather than scraping rendered HTML. The shop page uses `POST https://stage.api.drjoedispenza.com/api/v1/products/fetchProducts` with JSON like:

```json
{
  "shopByType": "categories",
  "shopSection": "Meditations",
  "page": 1,
  "paginationSize": 100,
  "sort": {},
  "filters": {},
  "searchTerm": "",
  "status": ["Active", "Coming Soon"]
}
```

Response shape: `data[0].metadata[0].total` and `data[0].data[]`, where each product has `title`, `images[]`, `pricing`, `variants[]`, and category metadata. At discovery time the Meditations category had 67 products; all had `images[]` suitable for album art. Use this API for catalog/art updates before falling back to browser scraping.

Known-good implementation in Erik's app repo: `/home/erix/Projects/meditation-player/scripts/fetch-shop-covers.py` downloads `images[0]` for every shop product into `public/shop-covers/`, writes `manifest.json` and `cover-map.json`, then `scripts/generate-catalog.py` prefers matched shop covers over generated SVGs. The matcher intentionally combines explicit mappings (e.g. BOTEC X/XI, Project Coherence, Count Your Blessings, Changing Boxes variants) with a high-threshold fuzzy match; avoid broad substring matching such as `"1" in "Advanced Workshop Vol. 1"`, which incorrectly assigns covers to workshop bundles.

To refresh the catalog safely from the server-backed media mirror:

```bash
cd /home/erix/Projects/meditation-player
rsync -a root@192.168.1.179:/mnt/tank/meditations/ /home/erix/Downloads/drive_to_truenas_meditations/Meditations/
python3 scripts/fetch-shop-covers.py
MEDIA_ROOT=/home/erix/Downloads/drive_to_truenas_meditations/Meditations python3 scripts/generate-catalog.py
npm run lint && npm run build
```

Verify after refresh: `public/shop-covers/` should contain one image file per shop product plus JSON manifests; `catalog.json` should retain the expected album/track counts; every `/shop-covers/...` referenced by the catalog should exist.

## Example Kubernetes storage

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: meditations-nfs-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  mountOptions:
    - nfsvers=4.1
    - ro
  nfs:
    server: 192.168.1.179
    path: /mnt/tank/meditations
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: meditations-nfs-pvc
  namespace: meditation-player
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 20Gi
  volumeName: meditations-nfs-pv
  storageClassName: ""
```

## Example nginx media block

```nginx
location /media/ {
  alias /usr/share/nginx/html/media/;
  autoindex off;
  add_header Accept-Ranges bytes always;
  add_header Cache-Control "private, max-age=3600" always;
  types {
    audio/mpeg mp3;
    audio/mp4 m4a;
    audio/flac flac;
    audio/ogg ogg;
    video/mp4 mp4;
    application/pdf pdf;
    application/zip zip;
    image/jpeg jpg jpeg;
    image/png png;
    image/webp webp;
  }
}
```

## Mobile UX for album/catalog players

For phone-width album libraries, avoid a "select album, then manually scroll past the whole album grid" flow. Use a compact selected-album detail and navigate the user to it:

- Keep album selection and track playback in the same page, but on `max-width: 900px` call `detailRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' })` after selecting an album.
- Set `scroll-margin-top` on the detail panel so sticky search/toolbars do not cover the album header.
- Hide non-essential hero/selected-album cards on mobile; they consume vertical space and delay access to playable tracks.
- On narrow phones, render the detail header as a small thumbnail plus text (`82px 1fr` worked for meditation-player) instead of a full-width cover.
- Verify the deployed CSS/JS, not just local build output: fetch the live HTML through Traefik with `curl --resolve`, then grep the hashed CSS/JS assets for the mobile rules and `scrollIntoView`.

## Pitfalls

- Do not mount SMB into Kubernetes for this pattern; NFS is simpler and already used in Erik's cluster.
- Keep the NFS export read-only unless the app truly needs writes.
- Remember that local `~/Projects/homelab` can lag `origin/main`; pull/fetch before adding manifests.
- For apps with media paths containing spaces/apostrophes/non-ASCII, catalog URLs must percent-encode each path segment, not the whole path with slashes encoded.
- When regenerating catalogs from TrueNAS media on the Hermes host, make sure `MEDIA_ROOT` points to a real local mirror or mounted path. The default `/mnt/tank/...` may not exist locally and can silently produce an empty `catalog.json`; verify album/track counts immediately after generation.
- For shop-cover matching, do not use naive substring matching or low fuzzy thresholds. Short titles/ordinals (`I`, `1`, `Vol. 1`) can collide with Advanced Workshop bundles and nearby sequels. Prefer explicit mappings for known variants and only overwrite an existing cover-map entry when the new score is higher.
- Flux image automation resource names matter. For meditation-player, reconcile `ImageUpdateAutomation/meditation-player` rather than a generic `flux-system`; if image automation already pushed the tag to `origin/main`, fetch/reconcile Git before assuming no update happened.
- If the app only has a local initial commit and no GHCR image yet, do not push/deploy without explicit user confirmation; creating repos/pushing images is external publishing.
