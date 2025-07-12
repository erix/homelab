# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a K3s homelab repository containing Kubernetes manifests for various self-hosted applications including media servers, home automation, and supporting infrastructure services. The repository currently uses manual kubectl/helm deployments with infrastructure ready for GitOps migration.

### Repository Layout
```
/Users/eriksimko/github/homelab/
├── k3s/
│   ├── apps/                # Main Kubernetes manifests directory
│   ├── helm/               # Helm charts and common library
│   │   ├── homelab-app/    # Standardized single-app chart
│   │   ├── homelab-common/ # Library chart for shared templates
│   │   └── home-assistant-stack/ # Multi-component stack chart
│   ├── ansible/            # Ansible inventory for cluster management
│   └── metallb_logs.sh     # MetalLB troubleshooting script
└── rdt-client/
    └── build-docker.sh     # Docker build script for ARM64
```

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
kubectl apply -f <application-name>/

# Check deployments
kubectl get deployments -n default
kubectl get statefulsets -n default
kubectl get pods -n default -o wide

# Check services and ingresses
kubectl get svc
kubectl get ingress

# View logs
kubectl logs -f <pod-name>

# Check node status
kubectl get nodes

# Describe resources
kubectl describe pod <pod-name>
kubectl describe svc <service-name>

# Execute commands in pods
kubectl exec -it <pod-name> -- /bin/bash
```

### Helm Operations
```bash
# Deploy using homelab-app chart
helm install <app-name> ./helm/homelab-app -f ./helm/homelab-app/values/<app-name>.yaml

# Upgrade existing deployment
helm upgrade <app-name> ./helm/homelab-app -f ./helm/homelab-app/values/<app-name>.yaml

# List helm releases
helm list

# Check helm values
helm get values <app-name>
```

## Current Architecture

### Cluster Nodes
- **homelab-control** (192.168.11.11): Control plane (Raspberry Pi)
- **homelab-02** (192.168.11.12): Worker node (Currently NotReady)
- **homelab-03** (192.168.11.13): Worker node (Hosts Zigbee USB device)
- **homelab-04** (192.168.11.14): Worker node (Database workloads)

### Cluster Components
- **K3s**: Lightweight Kubernetes distribution
- **Rancher**: Kubernetes management platform (cattle-* namespaces)
- **Traefik**: Ingress controller (deployed via Helm)
- **MetalLB**: Load balancer for bare metal (IP range: 192.168.11.200-250)
- **Longhorn**: Distributed storage solution with 3-way replication
- **Cert-Manager**: SSL certificate management (Let's Encrypt + Cloudflare)
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
- **Overseerr**: Media request management (running at 192.168.11.202:5055)
- **Calibre**: E-book management (running at 192.168.11.209:8080)
- **Calibre-Web**: Web interface for Calibre (running at 192.168.11.210:8083)
- **Readarr**: Book management (running)
- **Kometa**: Plex metadata manager
- **PlexTraktSync**: Plex-Trakt synchronization (cronjob)
- **Zurg**: Real-Debrid WebDAV server (running at 192.168.11.208:9999)

#### Home Automation
- **Home Assistant**: Smart home platform (StatefulSet, host networking at 192.168.11.207:8123)
- **Zigbee2MQTT**: Zigbee device bridge (running at 192.168.11.206:8080, nodeSelector: homelab-03)
- **Mosquitto**: MQTT broker (running at 192.168.11.230:8883)

#### Infrastructure
- **MariaDB**: MySQL-compatible database (StatefulSet at 192.168.11.203:3306, nodeSelector: homelab-04)
- **MongoDB**: NoSQL database (StatefulSet, nodeSelector: homelab-04)
- **Pi-hole**: Network-wide ad blocking (running at 192.168.11.222:53, NodePort for DHCP)
- **Unifi Controller**: Network management (configured but not deployed)
- **Open-WebUI**: AI chat interface (running)
- **Flaresolverr**: CloudFlare bypass proxy (running)
- **Filebrowser**: Web-based file manager
- **Algo-trader**: Trading application

### Networking Patterns
- **External Access**: Via Traefik ingress with SSL
- **LoadBalancer Services**: Using MetalLB for direct access
- **Host Networking**: Used by Home Assistant for device discovery
- **NodePort**: Used by Pi-hole for DHCP

### Deployment Methods
1. **Manual kubectl apply**: Primary method for applying manifests
2. **Helm Charts**: Used for infrastructure components (Traefik, Longhorn, etc.)
3. **ArgoCD Ready**: Repository structure supports GitOps but not currently active
4. **Common Helm Chart**: Custom chart at `helm/homelab-app/` for standardized deployments

## Development Workflow

1. Edit YAML manifests in appropriate application directory
2. Apply changes: `kubectl apply -f <app-directory>/`
3. Monitor deployment: `kubectl get pods -n default -w`
4. Check logs: `kubectl logs -f <pod-name>`
5. Verify ingress: `kubectl get ingress`

## Special Considerations

- **Node Placement**: 
  - Zigbee2MQTT: Must run on homelab-03 (USB device access)
  - MariaDB/MongoDB: Pinned to homelab-04 for database workloads
  - Check nodeSelector in deployments
- **Host Devices**: Zigbee2MQTT requires USB device access (`/dev/ttyUSB0`)
- **IP Reservations**: LoadBalancer services use MetalLB IP pool (192.168.11.200-250)
- **Persistent Storage**: StatefulSets maintain pod identity for storage consistency
- **Sealed Secrets**: Use `kubeseal` to encrypt sensitive data before committing
- **Host Networking**: Home Assistant uses host network mode for device discovery
- **Domain**: All ingresses use `*.erix-homelab.site` with wildcard TLS certificate

## Troubleshooting

### Common Issues
1. **Pod not starting**: Check `kubectl describe pod <pod-name>` for events
2. **Storage issues**: Verify PVC is bound with `kubectl get pvc`
3. **Network connectivity**: Check service endpoints with `kubectl get endpoints`
4. **MetalLB issues**: Run `./metallb_logs.sh` to collect diagnostic information
5. **Node issues**: Check node status with `kubectl describe node <node-name>`

## Common Helm Chart

A standardized Helm chart is available at `helm/homelab-app/` to reduce YAML duplication across applications.

### Chart Features
- **Smart Defaults**: Single replica, Traefik ingress class, erix-homelab.site domain
- **Wildcard TLS**: Automatically uses `erix-homelab-site-tls` secret for all ingresses
- **Flexible Storage**: Supports PVCs, NFS, hostPath, and existing volumes
- **Minimal Config**: Apps only need to specify unique values (image, ports, volumes)

### Usage Examples
```bash
# Deploy an application
helm install radarr ./helm/homelab-app -f ./helm/homelab-app/values/radarr.yaml

# Upgrade an application
helm upgrade radarr ./helm/homelab-app -f ./helm/homelab-app/values/radarr.yaml

# Deploy with custom values
helm install myapp ./helm/homelab-app --set name=myapp --set image.repository=myimage
```

### Creating New App Values
Create a minimal values file focusing only on app-specific settings:
```yaml
name: prowlarr
image:
  repository: linuxserver/prowlarr
service:
  ports:
    - name: http
      port: 9696
      targetPort: 9696
ingress:
  enabled: true  # Automatically creates prowlarr.erix-homelab.site
persistence:
  config:
    enabled: true
    size: 10Gi
    storageClassName: longhorn
```

### Common Patterns
- **Ingress**: Disabled by default, when enabled uses `{app}.erix-homelab.site` with TLS
- **Service**: ClusterIP by default, supports LoadBalancer with MetalLB annotations
- **Storage**: Multiple volume types supported in a single deployment
- **Environment**: Standard PUID/PGID/TZ variables for LinuxServer.io images

## Library Chart Migration

The repository includes a `homelab-common` library chart to standardize deployments:

### Using homelab-common
```yaml
# In Chart.yaml
dependencies:
  - name: homelab-common
    version: "0.1.0"
    repository: "file://../homelab-common"

# In templates/deployment.yaml
{{- include "homelab-common.deployment" (dict "root" $ "kind" "Deployment" "values" .Values.deployment) -}}

# In templates/service.yaml
{{- include "homelab-common.service" (dict "root" $ "values" .Values.service) -}}
```

This reduces template duplication and ensures consistency across all applications.