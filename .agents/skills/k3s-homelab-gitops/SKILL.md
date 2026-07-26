---
name: k3s-homelab-gitops
description: Use when changing or operating this k3s/Flux homelab repo.
version: 2.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [k3s, kubernetes, flux, gitops, homelab, github, ghcr]
    related_skills: [stateful-database-gitops-rollouts, systematic-debugging]
---

# Repository-local k3s Homelab GitOps Workflow

## Overview

Use this skill when changing manifests in this repository or operating the cluster reconciled from it. It is intentionally **harness- and workstation-neutral**: discover the checkout, binaries, kubeconfig, current context, remote revision, and execution host instead of assuming a username, home directory, or machine name.

The repository and live cluster are related but distinct sources of evidence:

1. `origin/main` shows what Flux is expected to consume.
2. The current checkout shows the proposed or reviewed change.
3. Flux status shows what revision controllers observed and applied.
4. Kubernetes status shows the actual running state.

Never print kubeconfig content, Kubernetes Secret data, registry credentials, application tokens, database rows, or decrypted SealedSecret material.

## When to use

Use this skill for:

- k3s, Kubernetes, Flux, Kustomize, Helm, ingress, storage, or workload work in this repository;
- adding or changing an application under `apps/` and its Flux descriptor under `clusters/`;
- Flux image scanning or image-update automation;
- backup-first upgrades and migrations covered by the linked references;
- checking whether Git, Flux, and the live cluster agree.

Do not use repository examples as universal Kubernetes defaults. Discover the live topology before acting, and treat values found only in old documentation as historical until confirmed.

## Portable session bootstrap

Run from any path inside the checkout. Do not hardcode `/home/<user>`, `~/Projects`, or a specific access host.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git fetch origin main
git status --short --branch
git rev-list --left-right --count HEAD...origin/main

K="${KUBECTL_BIN:-$(command -v kubectl || true)}"
F="${FLUX_BIN:-$(command -v flux || true)}"
H="${HELM_BIN:-$(command -v helm || true)}"

: "${KUBECONFIG:=$HOME/.kube/config}"
export KUBECONFIG

printf 'repo=%s\nkubeconfig=%s\nkubectl=%s\nflux=%s\nhelm=%s\n' \
  "$REPO_ROOT" "$KUBECONFIG" "$K" "$F" "$H"
```

Before cluster actions, require:

```bash
test -n "$K" && test -x "$K"
test -r "$KUBECONFIG"
"$K" config current-context
"$K" cluster-info
"$K" get nodes -o wide
```

If direct cluster access is unavailable, stop and use the harness's configured remote execution mechanism. A remote target may be an SSH host, CI runner, bastion, or agent gateway; **never assume one by name**. Verify the remote identity, working directory, binaries, kubeconfig, and Kubernetes context before running mutating commands there.

For read-only repository work, cluster access is optional. For rollout claims, it is mandatory.

## Discover current topology

Repository documentation can age. Derive current topology from manifests and live APIs:

```bash
# Git/Flux roots in the repository
git grep -nE 'kind: (GitRepository|Kustomization|ImageRepository|ImagePolicy|ImageUpdateAutomation)' -- clusters apps

git grep -nE 'path:|targetNamespace:|sourceRef:|image:|newTag:' -- clusters apps

# Live Flux resources
"$F" check --pre=false
"$F" get sources git -A
"$F" get kustomizations -A
"$F" get images repository -A
"$F" get images policy -A
"$F" get images update -A

# Live Kubernetes topology
"$K" get nodes -o wide
"$K" get ns
"$K" get deploy,statefulset,daemonset,cronjob -A -o wide
"$K" get svc,ingress -A -o wide
"$K" get sc,pv,pvc -A
```

If Helm is installed:

```bash
test -n "$H" && "$H" list -A
```

Use manifests under `clusters/new/flux-system/`, `clusters/new/apps/`, and `apps/` as the current structural guide. Confirm actual Flux paths and namespaces rather than relying on examples copied into prompts or old agent instructions.

## GitOps topology and deployment patterns

The usual repository pattern is:

1. A Flux `GitRepository` watches a branch.
2. A root `Kustomization` points at the cluster directory.
3. `clusters/new/apps/kustomization.yaml` includes per-application descriptors.
4. Each descriptor points to manifests under `apps/<app>` or, for selected applications, to another Git source.
5. Flux reconciles the selected revision into Kubernetes.

There are two common image flows.

### Application image built elsewhere, deployment stored here

1. An application repository publishes an immutable image tag or digest.
2. Flux `ImageRepository` scans the registry.
3. `ImagePolicy` chooses an eligible tag.
4. `ImageUpdateAutomation` updates a setter in this repository.
5. Flux applies the resulting commit.

### Application repository used directly as a Flux source

1. Flux watches the application repository.
2. Its Kustomization path contains deployable manifests.
3. Image automation may write back to that application repository rather than this one.

Always inspect `spec.sourceRef`, `spec.path`, checkout branch, update path, and setter marker. Do not infer ownership from an application name.

## Safe exploration

```bash
"$K" get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
"$K" get events -A --field-selector type=Warning --sort-by=.lastTimestamp

"$K" -n flux-system get \
  gitrepositories,kustomizations,imagerepositories,imagepolicies,imageupdateautomations

"$K" -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io -o json \
  | jq -r '.items[] | [.metadata.name, .spec.sourceRef.name, (.spec.path//""), (.spec.targetNamespace//""), (.status.conditions[]? | select(.type=="Ready") | .status), (.status.lastAppliedRevision//"")] | @tsv' \
  | sort
```

Do not dump Secret objects, kubeconfig, pod environments, or complete application configuration as a shortcut to diagnosis.

## Add a repository-managed application

1. Fast-forward from current remote state and require a clean base:
   ```bash
   cd "$REPO_ROOT"
   git fetch origin main
   git pull --ff-only origin main
   git status --short
   ```
2. Create `apps/<app>/` manifests and a `kustomization.yaml` when the application uses Kustomize.
3. Add `clusters/new/apps/<app>.yaml` with the correct source, path, prune behavior, dependencies, and target namespace.
4. Add the descriptor to `clusters/new/apps/kustomization.yaml`.
5. If image automation is required, add or update `ImageRepository`, `ImagePolicy`, and `ImageUpdateAutomation`, then place the correct setter marker beside the image tag.
6. For a private registry, configure both authentication boundaries without exposing values:
   - Flux image scanning: `ImageRepository.spec.secretRef` in the Flux namespace.
   - Kubelet image pull: `imagePullSecrets` in the workload namespace.
7. Validate rendered resources before commit:
   ```bash
   "$K" kustomize "apps/<app>" >/dev/null
   "$K" apply --dry-run=client -k "apps/<app>"
   git diff --check
   git diff -- apps/<app> clusters/new/apps
   ```
8. Commit and push only the reviewed files.
9. Reconcile in dependency order and verify the applied Git revision, workload rollout, image identity, logs, service, and user-visible endpoint.

## Reconcile and verify

```bash
"$F" reconcile source git flux-system
"$F" reconcile kustomization apps --with-source
"$F" reconcile kustomization <app> --with-source
"$F" get kustomization <app>

"$K" -n <namespace> rollout status deployment/<app> --timeout=300s
"$K" -n <namespace> get pods -l app=<app> -o wide
"$K" -n <namespace> logs deployment/<app> --tail=100
```

For StatefulSets, use `rollout status statefulset/<name>` and inspect storage/migration behavior. A Ready pod is not sufficient for schema-changing applications; load `stateful-database-gitops-rollouts`.

To force image controllers when applicable:

```bash
"$F" reconcile image repository <app> -n flux-system
"$F" reconcile image update <app> -n flux-system
```

Do not claim success until `GitRepository.status.artifact.revision`, the target Flux Kustomization's `lastAppliedRevision`, and the intended remote commit agree.

## Upgrade and operations references

Load only the reference matching the task:

- `references/home-assistant-upgrades.md`
- `references/zigbee2mqtt-upgrades.md`
- `references/pihole-upgrades.md`
- `references/immich-v3-vectorchord.md`
- `references/immich-v3-vectorchord-migration.md`
- `references/immich-remote-machine-learning.md`
- `references/unifi-mongodb-memory.md`
- `references/stremio-addon-upgrades.md`
- `references/private-ghcr-flux-apps.md`
- `references/static-site-ghcr-flux.md`
- `references/public-static-site-cloudflare-tunnel.md`
- `references/custom-domain-staging.md`
- `references/static-site-mailerlite.md`
- `references/truenas-media-webapps.md`
- `references/subscription-tracker-api.md`
- `references/home-network-naming.md`
- `references/unifi-dhcp-local-dns.md`
- `references/unifi-pihole-hostnames.md`
- `references/tailscale-routing.md`

Reference commands may contain repository-specific resource names and example addresses. Confirm them against current manifests and live resources before use. Environment paths and access hosts must always be discovered at runtime.

## Tailscale access decision

Before changing Kubernetes Services, distinguish:

1. **Per-service exposure** — expose selected Services through the Tailscale Kubernetes operator.
2. **Ingress exposure** — expose an ingress controller or use a Tailscale ingress class while retaining host-based routing.
3. **Subnet routing** — route client traffic to existing LAN/MetalLB networks through a separately configured Tailscale node.
4. **Exit-node routing** — route all client internet traffic; this is not required for homelab service access.

Use `references/tailscale-routing.md` to discover advertised routes, route approval, client acceptance, IP forwarding, IPv4/IPv6 egress, and HTTP reachability. Never hardcode a subnet-router host or CIDR from an example.

## Common pitfalls

1. **Machine-specific paths.** Never assume a username, home directory, checkout path, binary path, or kubeconfig path. Use the portable bootstrap.
2. **Wrong cluster context.** A valid kubeconfig can still point to the wrong cluster. Verify context, API endpoint, and nodes before mutation.
3. **Local checkout behind remote.** Fetch before reading or editing. The cluster follows remote Git, not an arbitrary local HEAD.
4. **Live-only edits.** Do not use `kubectl edit`, imperative annotation, or manual image changes as the final state when Flux owns the resource. Commit the intended state.
5. **Flux push races.** Image automation may push while an agent is editing. Fetch/rebase and check whether Flux already made the desired change.
6. **Shared setter paths.** Suspending one automation may not freeze setters updated by another automation sharing the same path. Verify the actual write boundary.
7. **Registry auth has two boundaries.** Flux scanning and kubelet pulling may use different namespace-local Secrets.
8. **Release tag assumptions.** A GitHub release tag may not exist as a container tag. Query the registry and pin a verified immutable digest.
9. **Ready is not end-to-end healthy.** Verify migrations, logs, service routing, authentication boundaries, and the user-visible behavior.
10. **Secret leakage.** Never inspect or print secret values to prove configuration.
11. **Ping-only diagnosis.** MetalLB or ingress endpoints may reject ICMP while TCP/HTTP works. Test the actual protocol.
12. **Exit node confusion.** Subnet routing and exit-node routing solve different problems. Test IPv4 and IPv6 egress before offering an exit node.

## Verification checklist

- [ ] Repository root and `origin/main` were discovered, not assumed.
- [ ] Required binaries and kubeconfig were discovered without reading secret contents.
- [ ] Kubernetes context and node identity match the intended cluster.
- [ ] Local changes are based on current remote state.
- [ ] Manifests render and pass client-side dry-run.
- [ ] No plaintext Secret or credential material was added.
- [ ] Remote commit, Flux source revision, and target applied revision agree.
- [ ] Target workload is Ready with stable restart count and intended immutable image.
- [ ] Relevant migrations, logs, Services, ingress routes, and user-visible behavior pass.
- [ ] Recent warning events were reviewed.
- [ ] Any backup created for a stateful change was verified and retained through the observation window.
