# Deployment workflow

Flux reconciles this repository from Git. This guide covers routine application
changes, adding a workload, validation, secrets, image automation, and rollback.

## Reconciliation model

The Flux bootstrap in `clusters/new/flux-system/` watches the `main` branch and
reconciles `clusters/new/`. The top-level `apps` Flux `Kustomization` then builds
`clusters/new/apps/`, whose `kustomization.yaml` enables individual workloads.

Each locally managed workload normally has two layers:

```text
clusters/new/apps/<name>.yaml  ->  apps/<name>/
       Flux configuration          Kubernetes resources
```

The Flux layer selects the source and path and may also set a target namespace,
image overrides, dependencies, health checks, or automation. Some entries
instead reference external Git repositories.

## Change an existing workload

1. Find the workload in `clusters/new/apps/kustomization.yaml`.
2. Read `clusters/new/apps/<name>.yaml` to identify its source and path.
3. Edit the referenced manifest files.
4. Validate the files and review the complete diff.
5. Commit and push the change.
6. Wait for reconciliation or trigger it explicitly.

```bash
flux reconcile kustomization <name> -n flux-system --with-source
flux get kustomization <name> -n flux-system
flux logs --kind=Kustomization --name=<name> -n flux-system
```

Then inspect the generated workload:

```bash
kubectl get all -n <namespace>
kubectl get ingress,pvc -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

## Add an in-repository workload

Create `apps/<name>/` with the required Kubernetes resources. Add a Flux
`Kustomization` at `clusters/new/apps/<name>.yaml`, following an existing nearby
workload with similar namespace and dependency requirements:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: example
  namespace: flux-system
spec:
  interval: 10m
  path: ../../apps/example
  prune: true
  targetNamespace: default
  sourceRef:
    kind: GitRepository
    name: flux-system
```

Omit `targetNamespace` when the manifests deliberately manage their own
namespace or contain resources for more than one namespace.

Finally, add `<name>.yaml` to `resources:` in
`clusters/new/apps/kustomization.yaml`. A per-workload file that is not listed
there is not part of the active app set.

Before enabling pruning, verify that the selected path contains only resources
owned by that Flux `Kustomization`. Removing an object from that path can cause
Flux to delete the live object.

## Add an external Git workload

Define a Flux `GitRepository`, then point the workload `Kustomization` at that
source. Use the Movie Night and Splitbot definitions under
`clusters/new/apps/` as current examples.

Pin or constrain the source appropriately. Add authentication through a
pre-provisioned secret reference when the repository is private; never place a
token in the manifest.

## Validation

Use the narrowest applicable validation:

```bash
# Formatting and whitespace errors
git diff --check

# Render a Kustomize application or overlay
kubectl kustomize apps/<name>

# Ask the API server to validate known resource types without persisting them
kubectl apply --server-side --dry-run=server -f apps/<name>/
```

The server-side dry run requires cluster access and any referenced CRDs to be
installed. If a directory does not contain a `kustomization.yaml`, validate its
YAML files individually or use the server-side directory dry run.

Also review:

- Namespace consistency between manifests and Flux `targetNamespace`
- PVC names, access modes, storage classes, and mount paths
- Services, selectors, container ports, and ingress backends
- Node selectors, affinity, host devices, and CPU architecture
- Sealed Secret names and the workloads that consume them
- Image policy markers and whether automation is suspended

## Secrets

Commit encrypted Sealed Secret resources. Do not commit newly created plaintext
`Secret` objects or decrypted values.

A typical flow is:

```bash
kubectl create secret generic <name> \
  --namespace <namespace> \
  --from-literal=<key>=<value> \
  --dry-run=client \
  --output=yaml \
| kubeseal \
  --format=yaml \
  --namespace <namespace> \
  --name <name>
```

Redirect the output to the intended sealed-secret file only after checking the
namespace and secret name. Avoid placing the plaintext value in shell history;
prefer a secure input or password-manager workflow where possible.

Existing plaintext-looking secret files may be retained for operational or
migration reasons, but they are not a pattern for new credentials.

## Image automation

Some workload definitions include `ImageRepository`, `ImagePolicy`, and
`ImageUpdateAutomation` resources. The automation writes selected image tags
back to Git.

Before modifying an image:

1. Inspect the policy tag filter and version range.
2. Check the update path and setter marker.
3. Check `spec.suspend`; a suspended automation represents an intentional
   manual rollout gate unless documented otherwise.
4. Confirm that related images that must stay in sync share compatible policy.

Useful status commands:

```bash
flux get images repository -A
flux get images policy -A
flux get images update -A
```

## Rollback

Rollback is a Git change:

1. Identify the last known-good manifest or image tag.
2. Revert or correct the relevant commit through the normal review workflow.
3. Push the change.
4. Reconcile the affected workload.
5. Verify both Flux readiness and application health.

```bash
flux reconcile kustomization <name> -n flux-system --with-source
flux describe kustomization <name> -n flux-system
kubectl rollout status -n <namespace> deployment/<name>
```

Do not rely on a manual `kubectl rollout undo` as the final rollback: Flux can
restore the Git-declared state on its next reconciliation.

## Removing a workload

Removal can delete live resources because pruning is enabled. Confirm data
retention requirements first, especially for PVCs and external databases.

The usual order is:

1. Decide whether persistent data must be retained or backed up.
2. Remove the workload entry from `clusters/new/apps/kustomization.yaml`.
3. Reconcile and verify the expected deletion.
4. Remove unused Flux definitions and manifests in a subsequent reviewed
   change.

Treat namespace deletion, PVC deletion, and secret removal as separate,
explicitly reviewed actions.
