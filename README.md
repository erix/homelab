# K3s Homelab

Kubernetes manifests for a self-hosted K3s homelab. The repository is reconciled
from Git by Flux and contains application workloads, cluster bootstrap resources,
supporting infrastructure configuration, and operational notes.

Repository-local operational skills for coding agents are available under
[`.agents/skills/`](.agents/skills/README.md).

> [!IMPORTANT]
> The files in this repository describe desired state. Use `flux get
> kustomizations -A` and `kubectl get pods -A` to verify the live cluster; do not
> infer runtime health from this README.

## How deployment works

Flux watches the `main` branch of
[`erix/homelab`](https://github.com/erix/homelab) and reconciles
`clusters/new/`. The deployment chain is:

```text
clusters/new/flux-system/gotk-sync.yaml
                    │
                    ▼
          clusters/new/apps.yaml
                    │
                    ▼
    clusters/new/apps/kustomization.yaml
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
       apps/*          external Git sources
```

Most in-repository workloads have:

- Kubernetes manifests in `apps/<name>/`
- A Flux `Kustomization` in `clusters/new/apps/<name>.yaml`
- An entry in `clusters/new/apps/kustomization.yaml`

Some workloads, including Movie Night and Splitbot, are reconciled from their
own Git repositories. Several workloads also use Flux image policies and image
update automation. Check the individual file before assuming image updates are
enabled; some automations are intentionally suspended.

## Repository layout

```text
.
├── .agents/skills/                # Repository-local operational skills
├── apps/                         # Application manifests
├── clusters/new/                 # Active Flux bootstrap and desired state
│   ├── apps.yaml                 # Parent Flux Kustomization
│   ├── apps/                     # Per-workload Flux resources
│   └── flux-system/              # Generated Flux controllers and sync config
├── infrastructure/               # Infrastructure manifests, values, and runbooks
├── docs/                         # Architecture and incident documentation
├── README.md                     # Repository overview
├── AGENTS.md                     # Canonical repository guidance for agents
└── CLAUDE.md                     # Points Claude-compatible tools to AGENTS.md
```

`infrastructure/argocd-apps/` is retained as legacy/reference configuration.
ArgoCD is not the active reconciliation path represented by `clusters/new/`.
Similarly, directories under `apps/` are not necessarily deployed merely
because they exist; the active inventory is
`clusters/new/apps/kustomization.yaml`.

## Flux-managed inventory

The active kustomization currently declares these groups:

| Group | Workloads |
| --- | --- |
| Networking | Traefik, mail relay |
| Home automation | MariaDB, Home Assistant, MQTT, Zigbee2MQTT |
| Storage | SSD-backed local-path provisioner |
| Media | RDT Client, Immich, Plex, Calibre, AIO Metadata, AIOStreams, Movie Night, Meditation Player |
| Network management | UniFi |
| Tools and services | n8n, Pastefy, IB Gateway, IBeam, Splitbot, Trading Dashboard, Subscription Tracker, Hello Confidence |
| External endpoints | TrueNAS Paperless, Jackettio and MinIO ingresses; Kaiburg and Proxmox ingresses; Splitbot tunnel |

This is a declaration inventory, not a runtime status list. For the exact and
current source of truth, read
[`clusters/new/apps/kustomization.yaml`](clusters/new/apps/kustomization.yaml).

## Architecture diagrams

The diagrams are generated from D2 sources in `docs/diagrams/`. Select an image
to open it at full resolution.

### Cluster architecture

[![K3s homelab declared architecture](docs/diagrams/architecture.png?v=21c0a0b2983f)](docs/diagrams/architecture.png)

Source: [`architecture.d2`](docs/diagrams/architecture.d2)

### Network paths

[![K3s homelab network paths](docs/diagrams/network-endpoints.png?v=12f65a15e1a5)](docs/diagrams/network-endpoints.png)

Source: [`network-endpoints.d2`](docs/diagrams/network-endpoints.d2)

### Storage backends

[![K3s homelab storage backends](docs/diagrams/storage-architecture.png?v=dbc2a7e00056)](docs/diagrams/storage-architecture.png)

Source: [`storage-architecture.d2`](docs/diagrams/storage-architecture.d2)

### Tailscale services

[![Tailscale-exposed Kubernetes services](docs/diagrams/tailscale-services.png?v=2322a915e7ee)](docs/diagrams/tailscale-services.png)

Source: [`tailscale-services.d2`](docs/diagrams/tailscale-services.d2)

## Working with the repository

### Prerequisites

- Access to the K3s cluster through `kubectl`
- The [Flux CLI](https://fluxcd.io/flux/cmd/) for reconciliation and status
  commands
- `kubeseal` when creating or rotating Sealed Secrets
- `kustomize` or `kubectl kustomize` for directories that contain a
  `kustomization.yaml`

### Normal change workflow

1. Edit the workload manifests or its Flux definition.
2. Validate the changed YAML and render Kustomize overlays where applicable.
3. Commit and push the change to `main` through the normal review workflow.
4. Let Flux reconcile it, or request an immediate reconciliation.
5. Verify the Flux object and resulting Kubernetes resources.

Useful commands:

```bash
# Flux reconciliation status
flux get sources git -A
flux get kustomizations -A
flux get images all -A

# Reconcile the repository and the top-level app set now
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization apps -n flux-system --with-source

# Reconcile and inspect one workload
flux reconcile kustomization <name> -n flux-system --with-source
flux logs --kind=Kustomization --name=<name> -n flux-system

# Inspect resulting resources
kubectl get pods -A
kubectl get ingress -A
kubectl get svc -A
kubectl get pvc -A
```

Avoid using `kubectl apply` as the normal deployment path for Flux-managed
resources. An uncommitted live-cluster edit can be reverted on reconciliation,
and a resource removed from Git can be deleted because pruning is enabled.

See [docs/deployment.md](docs/deployment.md) for adding workloads, validation,
secrets, image automation, and rollback guidance.

## Configuration conventions

- Workloads use a mix of explicit namespaces and Flux `targetNamespace`.
  Inspect both the app manifests and its Flux `Kustomization`.
- Traefik is the ingress controller represented in this repository.
- Persistent workloads use Longhorn, network storage, or the local SSD storage
  class according to their manifest.
- Device-bound workloads may use node selectors or host devices. Preserve those
  constraints when editing them.
- Commit Sealed Secrets, not newly created plaintext Kubernetes Secrets.
- Treat IP addresses, image tags, namespaces, storage classes, and hostnames in
  manifests as authoritative over narrative documentation.

## Troubleshooting

Start at the reconciliation layer, then inspect the Kubernetes resource:

```bash
# Why has desired state not applied?
flux get kustomizations -A
flux describe kustomization <name> -n flux-system
flux logs --kind=Kustomization --name=<name> -n flux-system

# Why is a workload unhealthy?
kubectl get pods -n <namespace> -o wide
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> <pod> --all-containers

# Storage and networking
kubectl get pvc -A
kubectl get ingress -A
kubectl get svc -A
```

For infrastructure-specific problems, use the runbooks under
`infrastructure/`. Historical incident analyses under `docs/` are useful
context, but their captured cluster state may no longer be current.

## Documentation

- [Repository-local agent skills](.agents/skills/README.md)
- [Deployment workflow](docs/deployment.md)
- [Infrastructure runbooks](infrastructure/README.md)
- [Tailscale integration](infrastructure/tailscale/README.md)
- [Longhorn notes](infrastructure/longhorn/README.md)
- [MetalLB notes](infrastructure/metallb/README.md)
- [Prometheus notes](infrastructure/prometheus/README.md)
- [Architecture diagrams](docs/diagrams/README.md)
- [Network architecture notes](docs/network-diagram.md)

The rendered diagrams are generated from repository-declared architecture.
Confirm live endpoints, allocated addresses, volume bindings, and workload
health with Flux and `kubectl` before making an operational change.
