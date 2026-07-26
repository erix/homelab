---
name: stateful-database-gitops-rollouts
description: Use when deploying schema-changing stateful apps via GitOps.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [gitops, kubernetes, sqlite, database, migrations, rollback]
    related_skills: [k3s-homelab-gitops, systematic-debugging]
---

# Stateful database GitOps rollouts

## When to use

Use this skill for a Kubernetes/GitOps release that changes an application's persistent database schema, especially SQLite applications with node-local storage, PVCs, automatic migrations, or binaries that reject newer schemas.

The goal is to separate code merge, deployment readiness, production activation, and feature enablement. A healthy pod is not enough evidence for a safe stateful rollout.

## Core workflow

1. Inspect remote Git, Flux state, the live workload, image automation, persistent volume mapping, current schema, and database integrity.
2. Freeze image movement at the real automation boundary. Shared setter paths can defeat per-app suspension.
3. Confirm every proposed feature flag is read and enforced by the exact code being deployed.
4. Stage Secrets, ConfigMaps, mounts, and fail-closed flags while the old image remains pinned. Reconcile and verify the old release still works.
5. Create and verify a database-native backup.
6. Restore that backup to a permission-restricted isolated copy and run the new migrations there.
7. Verify schema, integrity, foreign keys, required objects, and preservation of all legacy data.
8. Advance one immutable image pin and reconcile in dependency order.
9. Smoke public reads, authentication, CSRF, unauthorized mutation rejection, and every disabled feature gate.
10. Verify the live migrated database against the pre-migration restore point.
11. Keep the verified backup through the observation window and document the real rollback procedure.

For the detailed commands, invariants, hashing method, and pitfalls, read [references/stateful-sqlite-rollouts.md](references/stateful-sqlite-rollouts.md).

## Required evidence before success

- Remote Git and live Flux revisions match the intended commits.
- The running image is the exact reviewed immutable tag or digest.
- The pod is Ready with stable restart count.
- The database reports the expected schema version.
- SQLite integrity passes and foreign-key violations are zero.
- Legacy-column hashes match the verified pre-migration backup.
- An automatic or manual pre-migration restore point verifies at the old schema.
- Unauthorized mutations fail.
- Authenticated requests to disabled features fail closed.
- No proposals, receipts, audit events, or accounting changes appeared during a disabled rollout.
- Image automation remains frozen until explicitly re-enabled.

## Safety boundaries

- Never print database rows, account identifiers, raw brokerage payloads, credentials, cookies, or secret values as verification evidence.
- Never test a migration drill on the production database.
- Never continue a failed drill from a partially migrated scratch copy.
- Never treat a ConfigMap entry as a gate until code and route tests prove enforcement.
- Never promise image-only rollback when the old binary cannot read the new schema.
