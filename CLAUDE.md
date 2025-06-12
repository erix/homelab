# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a K3s homelab repository containing Kubernetes manifests for various self-hosted applications including media servers, home automation, and supporting infrastructure services. The repository appears to be configured for ArgoCD deployment but currently uses manual kubectl/helm deployments.

## Common Commands

### MetalLB Troubleshooting
```bash
./metallb_logs.sh  # Collects comprehensive MetalLB logs and creates metallb_report.tgz
```

### Docker Build (for rdt-client)
```bash
cd /Users/eriksimko/github/homelab/rdt-client
./build-docker.sh  # Builds ARM64 image for rdt-client
```

### Kubernetes Management
```bash
# Apply manifests manually
kubectl apply -f <application-name>/<manifest>.yaml

# Check deployments
kubectl get deployments -n default
kubectl get statefulsets -n default
kubectl get pods -n default -o wide
```

## Current Architecture

### Cluster Components
- **K3s**: Lightweight Kubernetes distribution
- **Rancher**: Kubernetes management platform (cattle-* namespaces)
- **Traefik**: Ingress controller (deployed via Helm)
- **MetalLB**: Load balancer for bare metal (IP range: 192.168.11.200+)
- **Longhorn**: Distributed storage solution
- **Cert-Manager**: SSL certificate management
- **Sealed Secrets**: Secret encryption (deployed via Helm)

### Storage Classes
- **longhorn** (default): General purpose distributed storage
- **longhorn-static**: For applications requiring specific volume binding
- **longhorn-db-storage**: Optimized for database workloads
- **nfs-books-csi**: NFS storage for books/media
- **nfs-downloads-csi**: NFS storage for downloads
- **smb**: SMB/CIFS network storage

### Application Structure
Each application typically includes:
- `*-deployment.yaml`: Kubernetes Deployment or StatefulSet
- `*-service.yaml`: Service definition (ClusterIP/LoadBalancer)
- `*-ingress.yaml`: Ingress rules for external access
- `*-pvc.yaml`: PersistentVolumeClaim if stateful

### Deployed Applications

#### Media Stack
- **Plex**: Media server (configured but not deployed)
- **Radarr**: Movie management (configured but not deployed)
- **Sonarr**: TV show management (configured but not deployed)
- **Prowlarr**: Indexer manager (running)
- **RDT-Client**: Real-Debrid torrent client (configured but not deployed)
- **Overseerr**: Media request management (running)
- **Calibre**: E-book management (running)
- **Calibre-Web**: Web interface for Calibre (running)
- **Readarr**: Book management (running)

#### Home Automation
- **Home Assistant**: Smart home platform (StatefulSet, host networking)
- **Zigbee2MQTT**: Zigbee device bridge (running)
- **Mosquitto**: MQTT broker (running)

#### Infrastructure
- **MariaDB**: MySQL-compatible database (StatefulSet)
- **MongoDB**: NoSQL database (StatefulSet)
- **Pi-hole**: Network-wide ad blocking (running)
- **Unifi Controller**: Network management (configured but not deployed)
- **Open-WebUI**: AI chat interface (running)
- **Flaresolverr**: CloudFlare bypass proxy (running)

### Networking Patterns
- **External Access**: Via Traefik ingress with SSL
- **LoadBalancer Services**: Using MetalLB for direct access
- **Host Networking**: Used by Home Assistant for device discovery
- **NodePort**: Used by Pi-hole for DHCP

### Deployment Methods
1. **Manual kubectl apply**: Primary method for applying manifests
2. **Helm Charts**: Used for infrastructure components (Traefik, Longhorn, etc.)
3. **ArgoCD Ready**: Repository structure supports GitOps but not currently active

## Development Workflow

1. Edit YAML manifests in appropriate application directory
2. Apply changes: `kubectl apply -f <app-directory>/`
3. Monitor deployment: `kubectl get pods -n default -w`
4. Check logs: `kubectl logs -f <pod-name>`
5. Verify ingress: `kubectl get ingress`

## Special Considerations

- **Node Placement**: Some apps may need specific nodes (check nodeSelector)
- **Host Devices**: Zigbee2MQTT requires USB device access
- **IP Reservations**: LoadBalancer services use MetalLB IP pool
- **Persistent Storage**: StatefulSets maintain pod identity for storage
- **Sealed Secrets**: Use `kubeseal` to encrypt sensitive data before committing