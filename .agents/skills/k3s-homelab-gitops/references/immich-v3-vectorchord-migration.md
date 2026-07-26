# Immich v3 VectorChord migration on Erik's k3s homelab

## Trigger

Use this reference when Immich server upgrades to `v3.x` and the server pod crash-loops with vector-extension errors.

Observed failure after Flux image automation upgraded Immich server/ML to `v3.0.x` while Postgres stayed on the old pgvecto.rs image:

```text
Error: No vector extension found. Available extensions: vchord, vector
microservices worker exited with code 1
Killing api process
```

Cluster symptoms:

```bash
kubectl -n immich get pods
# immich-server ... CrashLoopBackOff
# immich-postgres ... Running
# immich-machine-learning ... Running
```

## Root cause

Immich `v3.0.0+` drops pgvecto.rs support. Erik's manifests originally used:

```yaml
image: tensorchord/pgvecto-rs:pg14-v0.2.0
```

For the default Immich pg14 + pgvecto.rs 0.2.0 setup, migrate the DB container image to Immich's bundled Postgres image that includes VectorChord, pgvector, and the old pgvecto.rs extension for migration:

```yaml
image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

The image switch lets Immich create/use `vchord` and reindex during startup. Do not downgrade Immich below the migration-safe versions after this.

## Safe workflow

1. Confirm current state and exact error:

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl
F=/home/erix/.local/bin/flux

$K -n immich get deploy,sts,pod,svc,ingress,pvc -o wide
$K -n immich logs deploy/immich-server --previous --tail=200
$K -n immich exec immich-postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select extname, extversion from pg_extension order by extname; select name, default_version, installed_version from pg_available_extensions where name in ('"'"'vectors'"'"','"'"'vchord'"'"','"'"'vector'"'"') order by name;"'
```

2. Back up the database before changing the Postgres image. Do not print DB contents or secrets.

```bash
mkdir -p /home/erix/backups/immich
backup="/home/erix/backups/immich/immich-db-pre-vectorchord-$(date -u +%Y%m%dT%H%M%SZ).dump"
$K -n immich exec immich-postgres-0 -- sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-privileges' > "$backup"
ls -lh "$backup"
file "$backup"
sha256sum "$backup"
```

If local `pg_restore` is missing, validate the TOC inside the Postgres pod instead:

```bash
cat "$backup" | $K -n immich exec -i immich-postgres-0 -- pg_restore -l | sed -n '1,20p'
```

3. Update GitOps manifest in `/home/erix/Projects/homelab/apps/immich/postgres.yaml`:

```diff
- image: tensorchord/pgvecto-rs:pg14-v0.2.0
+ image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

4. Validate, commit, push, reconcile:

```bash
cd /home/erix/Projects/homelab
git fetch origin main && git pull --ff-only origin main
$K apply --dry-run=client -f apps/immich/postgres.yaml
git diff -- apps/immich/postgres.yaml
git add apps/immich/postgres.yaml
git commit -m "fix: migrate Immich Postgres to VectorChord image"
git push origin main
$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization immich --with-source
```

5. Verify rollout and migration:

```bash
$K -n immich rollout status statefulset/immich-postgres --timeout=300s
$K -n immich rollout status deploy/immich-server --timeout=300s
$K -n immich get pods -o wide
$K -n immich logs deploy/immich-server --tail=200
$K -n immich exec immich-postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -c "select name, default_version, installed_version, comment from pg_available_extensions where name like '\''%vector%'\'' or name like '\''%vchord%'\'' or name='\''vectors'\'' order by name;" -c "select extname, extversion from pg_extension order by extname;"'
```

Expected post-migration extensions include `vchord`, `vector`, and `vectors`.

6. Verify service/ingress:

```bash
curl -kfsS --max-time 10 -H 'Host: immich.erix-homelab.site' \
  https://192.168.11.200/api/server/ping
curl -kfsS --max-time 10 -H 'Host: immich.erix-homelab.site' \
  https://192.168.11.200/api/server/version
```

Expected:

```json
{"res":"pong"}
{"major":3,"minor":0,"patch":2,"prerelease":null}
```

## Follow-up check: machine learning URL

After the v3 migration, Immich may start but log:

```text
Machine learning server became unhealthy (http://192.168.1.90:3003)
```

In this session, the ML pod itself was healthy and answered `http://127.0.0.1:3003/ping`, but there was no Kubernetes Service for `immich-machine-learning`; Immich system config pointed at a fixed LAN IP (`http://192.168.1.90:3003`).

Future fix candidate: add an `immich-machine-learning` Service on port 3003 and update Immich system config to use in-cluster DNS such as `http://immich-machine-learning:3003`, after confirming the user's intended ML endpoint.

## Pitfalls

- Always back up Postgres before swapping the DB image. This is a database extension migration, not just an app rollout.
- Do not print secrets or dump table data. Extension lists and schema/TOC metadata are safe enough; DB rows are not.
- The first healthy server startup may spend time reindexing `clip_index` and `face_index`. Logs like `Reindexing clip_index` are expected; wait for `Immich Server is listening` unless there are errors.
- A 502 from ingress immediately after the DB image switch can be transient while Immich reindexes/starts. Recheck after rollout status and startup logs.
- If the previous Postgres image is not pg14/pgvecto-rs 0.2.0, adapt the Immich Postgres tag to match the previous Postgres major and pgvecto.rs version per upstream migration docs.
