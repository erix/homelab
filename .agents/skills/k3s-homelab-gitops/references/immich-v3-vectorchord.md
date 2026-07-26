# Immich v3 VectorChord migration on Erik's k3s homelab

Use when Immich server starts crash-looping after a v3 upgrade or logs vector-extension errors.

## Symptom observed

`immich-server` upgraded to `ghcr.io/immich-app/immich-server:v3.0.x` and crashed with:

```text
Error: No vector extension found. Available extensions: vchord, vector
microservices worker exited with code 1
```

Cluster state showed:

- `immich-server` CrashLoopBackOff
- `immich-machine-learning`, Redis, and Postgres running
- Postgres image still `tensorchord/pgvecto-rs:pg14-v0.2.0`
- Installed DB extension only `vectors|0.2.0`

## Root cause

Immich `v3.0.0+` drops support for the old `pgvecto.rs` extension path. The server image was advanced by Flux image automation, but the Postgres image under `apps/immich/postgres.yaml` was not migrated to Immich's VectorChord-capable Postgres image.

Immich's migration guide says: for the default old image `docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0`, switch to:

```text
ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

This image contains pgvector, VectorChord, and pgvecto.rs so existing backups/databases can migrate on Immich startup.

## Safe workflow

1. Gather state:

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl
F=/home/erix/.local/bin/flux

$F -n flux-system get kustomization immich
$K -n immich get deploy,sts,pod,svc,ingress,pvc -o wide
$K -n immich logs deploy/immich-server --previous --tail=200
$K -n immich exec immich-postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select extname, extversion from pg_extension order by extname;"'
```

2. Back up the DB before changing the Postgres image. Do not print data or secrets:

```bash
mkdir -p /home/erix/backups/immich
backup="/home/erix/backups/immich/immich-db-pre-vectorchord-$(date -u +%Y%m%dT%H%M%SZ).dump"
$K -n immich exec immich-postgres-0 -- sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-privileges' > "$backup"
file "$backup"
sha256sum "$backup"
```

3. Update `apps/immich/postgres.yaml`:

```diff
- image: tensorchord/pgvecto-rs:pg14-v0.2.0
+ image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

4. Validate, commit, push, and reconcile:

```bash
cd /home/erix/Projects/homelab
git pull --ff-only origin main
$K apply --dry-run=client -f apps/immich/postgres.yaml
git add apps/immich/postgres.yaml
git commit -m "fix: migrate Immich Postgres to VectorChord image"
git push origin main
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization immich --with-source
```

5. Verify migration/startup. Reindexing can take minutes; do not restart while logs say `Reindexing clip_index` / `Reindexing face_index` without errors:

```bash
$K -n immich rollout status statefulset/immich-postgres --timeout=300s
$K -n immich rollout status deploy/immich-server --timeout=300s
$K -n immich logs deploy/immich-server --tail=200
$K -n immich exec immich-postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -c "select name, default_version, installed_version from pg_available_extensions where name in ('"'"'vectors'"'"','"'"'vchord'"'"','"'"'vector'"'"') order by name;" -c "select extname, extversion from pg_extension order by extname;"'
```

Expected extensions after successful startup include:

```text
vchord  0.4.3
vector  0.8.1
vectors 0.2.0
```

6. Verify HTTP through Traefik:

```bash
curl -kfsS -H 'Host: immich.erix-homelab.site' \
  https://192.168.11.200/api/server/ping
curl -kfsS -H 'Host: immich.erix-homelab.site' \
  https://192.168.11.200/api/server/version
```

Expected:

```json
{"res":"pong"}
{"major":3,"minor":0,"patch":2,"prerelease":null}
```

## Follow-up pitfall

If Immich logs say `Machine learning server became unhealthy (http://192.168.1.90:3003)`, that is separate from the v3 crash-loop. In the observed setup the ML pod itself was healthy on port 3003, but Immich system config pointed at an old IP and there was no Kubernetes Service for `immich-machine-learning`. Fix separately by adding a stable service and repointing Immich ML URL; do not mix it into the VectorChord migration unless needed for user-facing smart-search features.
