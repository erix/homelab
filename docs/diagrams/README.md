# K3s homelab diagrams

The diagrams in this directory are generated from
[D2](https://d2lang.com/) source files and document repository-declared
architecture. They intentionally avoid live status, node uptime, dynamically
allocated addresses, and other details that become stale quickly.

## Diagram set

| Source | Rendered asset | Scope |
| --- | --- | --- |
| `architecture.d2` | `architecture.png` | Flux reconciliation, workload groups, cluster platform, and hardware constraints |
| `network-endpoints.d2` | `network-endpoints.png` | Ingress host groups, explicit LoadBalancer addresses, and external backends |
| `storage-architecture.d2` | `storage-architecture.png` | Storage classes, static NFS, existing PVC references, and host-bound storage |
| `tailscale-services.d2` | `tailscale-services.png` | Services explicitly annotated for Tailscale exposure |

The manifests and `clusters/new/apps/kustomization.yaml` remain the source of
truth. Verify the live system with Flux and `kubectl`.

## Render

Install D2, then run the script from anywhere in the repository:

```bash
# macOS
brew install d2 librsvg

# Render all PNG assets
./docs/diagrams/render.sh
```

The script renders each source to SVG with D2 and converts it to PNG with
`rsvg-convert`. This avoids D2's browser dependency for direct PNG output. It
checks that both tools are available before changing generated assets.

To render one diagram while editing:

```bash
cd docs/diagrams
d2 --watch --layout=dagre architecture.d2 architecture.svg

# After stopping watch mode:
rsvg-convert --format=png --output=architecture.png architecture.svg
```

Commit the `.d2` source and corresponding `.png` together.

## Maintenance checklist

When changing the deployment model:

1. Compare the diagram against `clusters/new/apps/kustomization.yaml`.
2. Confirm namespaces, ingress hosts, service annotations, static IPs, storage
   classes, NFS volumes, and host devices in the application manifests.
3. Update the D2 source.
4. Run `./docs/diagrams/render.sh`.
5. Visually inspect every generated PNG.

Do not add a runtime claim such as “running,” “healthy,” or “Ready” without
checking the live cluster and dating the claim.
