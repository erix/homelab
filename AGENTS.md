# Repository guidance for agents

This repository contains the desired state for a K3s homelab. Flux, not manual
`kubectl apply` or ArgoCD, is the active GitOps path represented by the current
repository structure.

## Repository-local skills

Reusable operational guidance lives under `.agents/skills/`. Before changing
manifests or operating the cluster, read
`.agents/skills/k3s-homelab-gitops/SKILL.md` and load only the references
relevant to the task. For schema-changing stateful releases, also read
`.agents/skills/stateful-database-gitops-rollouts/SKILL.md`.

The skills are workstation-neutral. Discover the repository root, tools,
kubeconfig, Kubernetes context, and any remote execution target instead of
assuming paths or hostnames.

## Source of truth

Read these files in order when determining what is deployed:

1. `clusters/new/flux-system/gotk-sync.yaml` — Flux source and cluster path
2. `clusters/new/apps.yaml` — top-level application reconciliation
3. `clusters/new/apps/kustomization.yaml` — enabled workload inventory
4. `clusters/new/apps/<name>.yaml` — source, path, namespace, dependencies, and
   image policy for one workload
5. `apps/<name>/` or the referenced external Git repository — Kubernetes
   resources

A directory under `apps/` is not proof that Flux deploys it. Conversely, some
Flux workloads use external Git sources and therefore have no local app
directory.

`infrastructure/argocd-apps/` is legacy/reference configuration. The incident
reports and diagrams under `docs/` capture useful historical context, but
manifests take precedence when details conflict.

## Repository layout

```text
apps/                    Application manifests
clusters/new/            Active Flux bootstrap and reconciliation resources
infrastructure/          Infrastructure manifests, Helm values, scripts, runbooks
docs/                    Architecture, deployment, and incident documentation
```

## Safe change workflow

For a Flux-managed workload:

1. Inspect its entry under `clusters/new/apps/`.
2. Edit the referenced manifests.
3. If adding or removing a workload, update both its per-workload Flux resource
   and `clusters/new/apps/kustomization.yaml`.
4. Validate all changed YAML. Render any directory with a
   `kustomization.yaml`.
5. Review the diff for unintended secrets, mutable tags, namespace changes,
   storage changes, and pruning effects.
6. Commit and push through the normal review workflow; Flux applies the desired
   state.
7. Verify reconciliation and the resulting objects.

Do not make manual cluster mutation the primary implementation unless the user
explicitly requests an emergency or diagnostic action. Flux can revert drift,
and most Flux `Kustomization` resources in this repository have pruning enabled.

## Common commands

```bash
# Repository validation
git diff --check
kubectl kustomize apps/<name>  # when the directory has kustomization.yaml

# Flux status and reconciliation
flux get sources git -A
flux get kustomizations -A
flux get images all -A
flux reconcile kustomization <name> -n flux-system --with-source
flux logs --kind=Kustomization --name=<name> -n flux-system

# Kubernetes verification
kubectl get pods -A -o wide
kubectl get ingress -A
kubectl get svc -A
kubectl get pvc -A
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> <pod> --all-containers
```

See `docs/deployment.md` for the complete deployment workflow.

## Important conventions

- Check both `metadata.namespace` in application manifests and
  `spec.targetNamespace` in the Flux resource.
- Preserve node selectors, affinity, host networking, host devices, and
  architecture constraints. Some workloads depend on specific hardware.
- Treat PVC, storage-class, database, and namespace changes as migration work,
  not routine edits.
- Prefer immutable or policy-managed image tags. Inspect the associated
  `ImageUpdateAutomation`; some are intentionally suspended.
- Use Sealed Secrets for credentials. Do not add new plaintext Secret manifests,
  credentials, tokens, kubeconfigs, or decrypted values to Git.
- Generated files under `clusters/new/flux-system/` say `DO NOT EDIT`; update
  them only through the Flux bootstrap/update workflow.
- Do not update runtime versions, node health, uptime, or endpoint availability
  in narrative docs without checking the live cluster.
- Preserve unrelated working-tree changes.

## Operational checks

When debugging, follow the dependency chain:

1. Confirm the Git source is ready.
2. Confirm the parent `apps` Kustomization is ready.
3. Confirm the workload Kustomization is ready.
4. Inspect events and health for the resulting Kubernetes objects.
5. For network or storage failures, consult the relevant runbook under
   `infrastructure/`.

Useful diagnostics include:

```bash
flux describe source git flux-system -n flux-system
flux describe kustomization apps -n flux-system
flux describe kustomization <name> -n flux-system
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

The repository contains historical troubleshooting and migration documents.
Keep their dates and context intact rather than rewriting them as current-state
documentation.
