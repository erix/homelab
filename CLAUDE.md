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

## Cluster Stability and Known Issues

### Hardware Characteristics
- **CPU**: Raspberry Pi 4, 4-core ARM64
- **Memory**: 4GB RAM per node
- **Storage**: USB 3.0 flash drives (~150MB/s read, variable write speeds)
- **Constraint**: Resource-limited hardware requires careful tuning

### Known Stability Issues (Resolved 2025-10-20)

#### Problem: Cascading Failures and Pod Concentration
The cluster experienced recurring cascading failures where:
1. Initial trigger (snapshot, probe timeout, or load spike)
2. Health probes fail → pods restart → more load → more failures
3. Node becomes NotReady → pods migrate to other nodes
4. **Pods permanently concentrate on one node** (e.g., 36 pods on homelab-03)
5. Overloaded node at risk of another cascade

**Root Causes Identified**:
1. **Aggressive health check timeouts** (1s) too strict for ARM hardware under load
2. **Overlapping Longhorn snapshots** at midnight-1 AM causing I/O spikes
3. **High concurrent Longhorn operations** (5 rebuilds) overwhelming nodes
4. **No resource limits** on Prometheus allowing unbounded memory/CPU consumption
5. **No pod distribution policy** - Kubernetes doesn't auto-rebalance pods
6. **No swap** - OOM killer activates under memory pressure
7. **Slow iptables operations** under load (91 seconds for ChainExists)

#### Solutions Implemented

**Critical Fixes (Applied 2025-10-20)**:

1. **Health Check Optimization** (`prometheus/health-check-values.yaml`, `metallb/values.yaml`)
   - Increased probe timeouts: 1s → 5s
   - Increased failure threshold: 3 → 5 failures
   - Increased period: 10s → 15s
   - Grace period before restart: 3s → 25s
   - **Impact**: Eliminated false-positive restarts (7,444 restarts → 0)

2. **Longhorn Snapshot Staggering** (via kubectl patch)
   ```
   database-snapshot: 0 0 * * ?     (midnight)
   app-snapshot:      0 3 * * ?     (3 AM, was 1 AM)
   database-backup:   0 2 ? * MON   (Monday 2 AM)
   app-backup:        0 2 ? * WED   (Wednesday 2 AM, was Monday)
   ```
   - **Impact**: Eliminated midnight I/O spike pattern

3. **Longhorn Concurrent Operations** (`longhorn/current-values.yaml`)
   - Reduced concurrent replica rebuilds: 5 → 2 per node
   - Reduced concurrent backup/restore: 5 → 2 per node
   - Increased rebuild wait interval: 600s (10 minutes)
   - Allow degraded volume creation: true
   - **Impact**: Prevents rebuild cascades

4. **Prometheus Resource Limits** (`prometheus/health-check-values.yaml`)
   ```yaml
   prometheus:     500m-2 CPU, 2-4Gi memory
   alertmanager:   100m-500m CPU, 256-512Mi memory
   grafana:        250m-1 CPU, 512Mi-1Gi memory
   ```
   - Pod anti-affinity to spread across nodes
   - **Impact**: Prevents unbounded resource consumption

5. **Automatic Pod Distribution** (Topology Spread Constraints)
   - Applied to ALL 32 deployments + 2 StatefulSets
   - Configuration: `maxSkew: 1, whenUnsatisfiable: ScheduleAnyway`
   - Tool: `apply-topology-spread.sh` for automation
   - **Impact**: Future pods automatically spread evenly across nodes

**How to Trigger Rebalancing**:
```bash
cd /Users/eriksimko/github/homelab/k3s/apps
./apply-topology-spread.sh restart
```

### Monitoring Cluster Health

**Check Pod Distribution**:
```bash
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | grep -E "homelab" | sort | uniq -c | sort -rn
```
Expected: ~16 pods per node (±2)

**Check Node Load**:
```bash
kubectl top nodes
# Healthy: Load <8 (2x CPU count)
# Warning: Load >8
# Critical: Load >16
```

**Check for Terminating Pods** (sign of zombie pod issue):
```bash
kubectl get pods -A | grep Terminating
```

**Force Delete Terminating Pods** (if node is NotReady):
```bash
kubectl get pods -A --field-selector spec.nodeName=homelab-02 -o json | \
  jq -r '.items[] | select(.metadata.deletionTimestamp != null) |
  "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns pod; do
    kubectl delete pod -n $ns $pod --grace-period=0 --force
  done
```

### Emergency Recovery Procedures

**If Node Goes NotReady**:
1. **Don't panic** - Let it settle for 5-10 minutes
2. **Check load**: `ssh <node> "uptime"`
3. **Look for zombie pods**: `kubectl get pods -A | grep Terminating`
4. **If zombies exist**: Force-delete them (command above)
5. **If still stuck after 15 min**: Restart k3s-agent on the node

**If Pod Concentration Occurs**:
1. Verify topology spread is applied: `kubectl get deployment <name> -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'`
2. Trigger rebalancing: `./apply-topology-spread.sh restart`
3. Monitor distribution: `kubectl get pods -A -o wide`

### Documentation References

For detailed information about cluster stability:
- `CASCADING_FAILURE_ANALYSIS.md` - Root cause analysis of 7 failure triggers
- `PREVENTION_PLAN.md` - Comprehensive prevention strategy (11 fixes)
- `FIXES_APPLIED.md` - Detailed changelog of applied fixes
- `POD_DISTRIBUTION_STRATEGY.md` - Long-term pod distribution strategy
- `POD_DISTRIBUTION_FIX_SUMMARY.md` - Implementation summary
- `metallb/README.md`, `prometheus/README.md`, `longhorn/README.md` - Component-specific docs

### Success Metrics (Post-Fix)

**Before (2025-10-20 morning)**:
- Prometheus node-exporter: 7,444 restarts on homelab-03
- MetalLB speaker: 21 restarts on homelab-02
- homelab-02 NotReady event with load 60.09 (15x normal)
- Pod distribution: 36 pods on homelab-03, 12 on homelab-02, 12 on homelab-04

**After (2025-10-20 evening)**:
- All components stable with 0 restarts
- Cluster recovered from NotReady in <10 minutes
- Topology spread constraints applied to all deployments
- I/O load staggered across different times/days

**Target Ongoing**:
- Zero NotReady events over 7 days
- Balanced pod distribution (±2 pods per node)
- Node load <8 during normal operations
- No probe timeout restarts