# Stateful SQLite rollout procedure

## Release gates

1. **Freeze image movement.** Suspend image automation and inspect its effective write scope. If other automations share the setter directory, remove the target app's setter marker or narrow all automation paths. Confirm the pin in remote Git and live `Kustomization.spec.images`.
2. **Prove application gates exist.** Search the built code for every configured feature flag. A ConfigMap key is not a safety control unless the deployed code reads and enforces it. Test the disabled route.
3. **Stage prerequisites before the image.** Commit and reconcile Secrets, ConfigMaps, volume mounts, and fail-closed flags while the old image remains pinned. Verify the old image stays healthy after the rollout.
4. **Create a WAL-safe backup.** Use the application's backup command or SQLite backup API rather than copying the database file blindly. Verify integrity and source schema without exposing row contents.
5. **Run an isolated restore/migration drill.** Copy the verified backup to a permission-restricted temporary location. Start from a fresh copy on every retry. Run new migrations against only that copy.
6. **Verify the migrated copy.** Require the expected schema, `PRAGMA integrity_check = ok`, zero foreign-key violations, and expected tables/indexes.
7. **Prove legacy data preservation.** Hash each pre-migration table's original columns in stable row order. After migration, hash those same columns, not newly added columns. Emit only booleans and counts.
8. **Advance one immutable image pin.** Reconcile the parent descriptor and workload Kustomization, then wait for rollout health.
9. **Smoke both sides of authorization.** Check public reads, unauthenticated mutation rejection, authenticated login, CSRF enforcement, and authenticated rejection for every disabled feature.
10. **Verify live data after migration.** Compare live legacy-column hashes to the verified backup, confirm the pre-migration restore point, and ensure mutation/audit tables remain empty during a read-only rollout.
11. **Clean temporary copies.** Retain approved backups, but remove copied databases and smoke scripts from temporary locations.

## Deterministic legacy-data comparison

For each legacy table:

1. Read the column list from the schema-older backup.
2. Query only those columns in stable row order.
3. Hash a deterministic serialization of every row.
4. Run the same query against the migrated database.
5. Compare digests without printing records.

Do not recompute the post-migration column list. Added columns cause false mismatch reports even when every legacy value is intact.

## Rollback rule

Check whether the old binary refuses databases newer than its supported schema. If it does, rollback is **image plus database restore**, not image-only. Preserve the verified pre-migration backup through the observation window and state this constraint before rollout.

## Durable pitfalls

- A Deployment hostPath belongs to the Kubernetes node, not necessarily the machine running `kubectl`. Use `kubectl cp` or a controlled pod-side operation if it is not locally mounted.
- Restart every failed drill from a fresh verified backup copy. A transaction may protect one migration while earlier numbered migrations remain committed in the scratch database.
- Python scripts launched from a shared temporary directory can import unrelated files that shadow standard-library modules. Use safe-path mode (`python -P`) or an isolated script directory.
- Reconcile dependencies in order: Git source or parent app descriptor, then workload Kustomization, then rollout status.
- Pod readiness does not prove route health, authorization, gate enforcement, schema correctness, or data preservation. Verify each directly.
- Do not claim rollback readiness until a restore has been exercised, not merely a backup created.
