# Private GHCR app deployment pattern in this repository's homelab

Use this when adding a private GitHub app repo that publishes a private GHCR image and is deployed from `erix/homelab` via Flux.

## Known-good pattern

1. Keep the app repo private, but make sure GitHub Actions has:
   ```yaml
   permissions:
     contents: read
     packages: write
   ```
2. Build and push to GHCR using `GITHUB_TOKEN` and publish both `latest` and a Flux-sortable immutable tag. For `main` branch apps:
   ```yaml
   tags: |
     type=raw,value=latest,enable={{is_default_branch}}
     type=raw,value=main-${{ github.run_number }}-sha-${{ github.sha }},enable={{is_default_branch}}
     type=sha,prefix=sha-
   ```
3. In the app `Deployment`, add the pull secret in the workload namespace:
   ```yaml
   spec:
     template:
       spec:
         imagePullSecrets:
           - name: ghcr-credentials
   ```
4. Ensure the same dockerconfig secret exists in the app namespace. The cluster has `ghcr-credentials` in `default` and `flux-system`; for a dedicated namespace, copy/apply metadata only without printing secret data:
   ```bash
   : "${KUBECONFIG:=$HOME/.kube/config}"
export KUBECONFIG
   K="${K:-$(command -v kubectl)}"
   $K get namespace <app> >/dev/null 2>&1 || $K create namespace <app>
   $K -n default get secret ghcr-credentials -o yaml \
     | python3 -c 'import sys,yaml; d=yaml.safe_load(sys.stdin); d["metadata"]={"name":"ghcr-credentials","namespace":"<app>"}; print(yaml.safe_dump(d, sort_keys=False))' \
     | $K apply -f -
   ```
   Do not print or inspect `.data`.
5. Add Flux image automation in `clusters/new/apps/<app>.yaml`:
   ```yaml
   spec:
     images:
       - name: ghcr.io/erix/<app>
         newTag: latest # {"$imagepolicy":"flux-system:<app>:tag"}
   ---
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImageRepository
   metadata:
     name: <app>
     namespace: flux-system
   spec:
     image: ghcr.io/erix/<app>
     interval: 1m
     secretRef:
       name: ghcr-credentials
   ---
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImagePolicy
   metadata:
     name: <app>
     namespace: flux-system
   spec:
     imageRepositoryRef:
       name: <app>
     filterTags:
       pattern: "^main-(?P<run>[0-9]+)-sha-[a-f0-9]{40}$"
       extract: "$run"
     policy:
       numerical:
         order: asc
   ---
   apiVersion: image.toolkit.fluxcd.io/v1beta1
   kind: ImageUpdateAutomation
   metadata:
     name: <app>
     namespace: flux-system
   spec:
     interval: 1m
     sourceRef:
       kind: GitRepository
       name: flux-system
     git:
       checkout:
         ref:
           branch: main
       commit:
         author:
           email: fluxcdbot@users.noreply.github.com
           name: fluxcdbot
         messageTemplate: "chore: update <app> image"
       push:
         branch: main
     update:
       path: ./clusters/new/apps
       strategy: Setters
   ```

## Verification

```bash
: "${KUBECONFIG:=$HOME/.kube/config}"
export KUBECONFIG
F="${F:-$(command -v flux)}"
K="${K:-$(command -v kubectl)}"

$F reconcile source git flux-system
$F reconcile kustomization apps --with-source
$F reconcile kustomization <app> --with-source
$F reconcile image repository <app> -n flux-system
$F get images repository <app> -n flux-system
$F get images policy <app> -n flux-system
$F reconcile image update <app> -n flux-system
$K rollout status deployment/<app> -n <namespace> --timeout=180s
$K get deploy,pod,svc,ingress,pvc -n <namespace> -o wide
```

## Pitfalls

- A private GitHub repo can still deploy cleanly if GHCR auth is configured; do not make the repo or package public just to avoid an image pull problem.
- `ImageRepository` must use `secretRef: ghcr-credentials`; otherwise Flux may not scan private packages.
- `Deployment.imagePullSecrets` must be in the workload namespace, not just `flux-system`.
- Flux `ImageUpdateAutomation` may report `no updates made` if the target tag is already in Git (possibly due to another Flux commit racing ahead). Verify the actual `newTag` in `origin/main` and the deployed pod image.
- If `git push` to homelab is rejected, fetch/rebase because Flux image automations may have pushed another commit to `main`.
