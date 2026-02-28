# rdt-client + FileBot Stack

## Overview

This stack handles media acquisition and library organization:

```
Real-Debrid (cloud) → rdt-client (download) → FileBot AMC (rename/symlink) → Plex (serve)
```

## Architecture

All components run in a **single pod** (`rdt-client` namespace) as sidecars sharing the pod network (`localhost`) and NFS volumes.

### Containers

| Container | Image | Role |
|-----------|-------|------|
| `rdt-client` | `erix12/rdt-client-manual-download` | Downloads from Real-Debrid to NFS |
| `filebot` | `jlesage/filebot` | AMC watcher (hourly fallback) |
| `filebot-trigger` | `jlesage/filebot` | HTTP trigger server (primary, port 9999) |
| `filebot-license-init` | `jlesage/filebot` | Init container: installs license |

### Volume Mounts

| NFS Path (TrueNAS) | Mount in pod | Used by |
|--------------------|-------------|---------|
| `tank/downloads/rdt` | `/downloads` | rdt-client, filebot, filebot-trigger |
| `tank/media/plex` | `/media` | filebot, filebot-trigger |

**Critical**: Both FileBot containers and Plex must share the **same mount paths** so symlinks resolve correctly.

Plex mounts:
- `tank/downloads/rdt` → `/downloads` (symlink targets)
- `tank/media/plex` → `/media` (symlink source, Plex library)

## Download → Library Flow

1. **rdt-client** downloads torrent to `/downloads/<TorrentName>/`
2. On completion, rdt-client calls:
   ```
   curl -s -X POST http://localhost:9999 -d "%D"
   ```
   where `%D` = the full torrent folder path (e.g. `/downloads/Movie.Name.2024.2160p.../`)
3. **filebot-trigger** HTTP server receives the path, runs FileBot AMC on that specific folder
4. **FileBot AMC** renames and creates symlinks:
   - Source: `/downloads/<TorrentName>/<file>.mkv`
   - Symlink: `/media/Movies/<Movie Name> {tmdb-ID}/<Movie Name> [edition, resolution, hdr].mkv`
5. FileBot notifies Plex via API to scan the updated library section
6. **Plex** detects new symlinks and adds them to the library

## FileBot AMC Config

| Setting | Value |
|---------|-------|
| Action | `symlink` (no copy/move — saves space) |
| Output | `/media` |
| Movie format | `{ plex.id % " [" % {edition} % ", " % {vf} % ", " % {hdr} %"]" }` |
| Series format | same as movie |
| Conflict | `skip` |
| Excludes list | `/media/.excludes` |
| Plex notify | `plex.erix-homelab.site` |
| Discord notify | webhook configured |

## rdt-client Hook Settings (SQLite)

Stored in `/data/db/rdtclient.db`, table `Settings`:

| Key | Value |
|-----|-------|
| `General:RunOnTorrentCompleteFileName` | `curl` |
| `General:RunOnTorrentCompleteArguments` | `-s -X POST http://localhost:9999 -d %D` |

Available `%` variables from rdt-client:
- `%N` = torrent name
- `%D` = full torrent folder path (use this for AMC input)
- `%F` = single file path (or folder if multiple files)
- `%L` = category
- `%I` = hash

## Fallback

The main `filebot` container runs AMC on the full `/downloads` directory every **1 hour** as a fallback (in case the trigger misses anything). It uses directory hash change detection — only runs if something actually changed.

## Troubleshooting

### Check trigger server logs
```bash
kubectl logs -n rdt-client <pod> -c filebot-trigger
```

### Check AMC watcher logs
```bash
kubectl logs -n rdt-client <pod> -c filebot
```

### Manually trigger AMC on a specific folder
```bash
kubectl exec -n rdt-client <pod> -c rdt-client -- \
  curl -s -X POST http://localhost:9999 -d "/downloads/Movie.Name.2024"
```

### Reset excludes list (force re-scan all)
```bash
kubectl exec -n rdt-client <pod> -c filebot -- rm /media/.excludes
```

### Check broken symlinks in Plex library
```bash
kubectl exec -n plex plex-0 -- find /media -type l | xargs -I{} sh -c 'test -e "{}" || echo "BROKEN: {}"'
```
