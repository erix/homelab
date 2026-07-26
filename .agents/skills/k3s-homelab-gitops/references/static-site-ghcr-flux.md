# Static website: GitHub → GHCR → Flux

Use this pattern for a static HTML/CSS/JS repository that must update the k3s site after a normal Git push, while source and image remain private.

## Design

1. Verify the repository default branch; trigger on that branch (`main` is common—do not assume `master`).
2. Add a small `Dockerfile` based on a pinned nginx alpine tag:
   ```dockerfile
   FROM nginx:1.27-alpine
   COPY . /usr/share/nginx/html/
   EXPOSE 80
   ```
3. Add `.dockerignore` for `.git`, `.github`, OS junk, and other non-site files.
4. Add a GitHub Actions workflow with `contents: read` and `packages: write`. On each default-branch push, log into `ghcr.io` with `${{ secrets.GITHUB_TOKEN }}`, build the image, and publish both:
   - `latest` for initial/manual use
   - an immutable Flux-sortable tag: `main-<github.run_number>-sha-<full github.sha>`
5. In the homelab repository, deploy an nginx-backed `Deployment`, `Service`, and Traefik `Ingress`. Add a `Kustomization`, `ImageRepository`, numeric `ImagePolicy`, and `ImageUpdateAutomation` following the private-GHCR pattern.
6. Include `imagePullSecrets: [{name: ghcr-credentials}]` in the workload. The Flux `ImageRepository` also needs `secretRef: ghcr-credentials`.

## Workflow essentials

Use the current major Docker actions (`checkout`, `setup-buildx-action`, `login-action`, `metadata-action`, `build-push-action`) and cache through `type=gha`. Use `docker/metadata-action` raw tags, with the branch-specific immutable tag rendered by GitHub expressions.

Set the package source label through the metadata action so the GHCR package is associated with its repository. For a private image outside the `erix` account, confirm the package inherits repository permissions (or explicitly grants the account represented by `ghcr-credentials` pull access) before relying on Flux.

## Verification order

1. Run `docker build` locally and serve the image on a temporary localhost port; check the response contains the expected page title.
2. Render and client-dry-run the app manifests plus Flux resources.
3. Commit/push the website workflow first; wait for the GitHub Actions package publication to complete successfully.
4. Commit/push the GitOps manifests, then reconcile Flux source, app Kustomization, ImageRepository, and image update automation.
5. Verify the deployed pod image is the immutable tag chosen by policy, readiness is true, the ingress has the intended host/TLS secret, and HTTPS returns the page.

## DNS migration

A hostname migration is an ingress-only GitOps change: replace/add the host under `rules` and `tls.hosts`, commit to `erix/homelab`, reconcile, then verify TLS and host routing. The website image pipeline stays unchanged.
