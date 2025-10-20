# K3s Homelab

A production-ready Kubernetes homelab running on Raspberry Pi cluster, featuring automated media management, home automation, and self-hosted services.

![Kubernetes](https://img.shields.io/badge/kubernetes-326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![K3s](https://img.shields.io/badge/k3s-FFC61C?style=for-the-badge&logo=k3s&logoColor=black)
![Raspberry Pi](https://img.shields.io/badge/-RaspberryPi-C51A4A?style=for-the-badge&logo=Raspberry-Pi)
![Helm](https://img.shields.io/badge/helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)
![Longhorn](https://img.shields.io/badge/longhorn-FF4F00?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJMMiA3djEwYzAgNS41MiA0LjQ4IDEwIDEwIDEwczEwLTQuNDggMTAtMTBWN2wtMTAtNXoiLz48L3N2Zz4=)
![Home Assistant](https://img.shields.io/badge/home%20assistant-41BDF5.svg?style=for-the-badge&logo=home-assistant&logoColor=white)
![Grafana](https://img.shields.io/badge/grafana-F46800.svg?style=for-the-badge&logo=grafana&logoColor=white)

## Overview

This repository contains Kubernetes manifests and Helm charts for a self-hosted homelab running on a 4-node K3s cluster. The infrastructure supports media automation, home automation, network services, and monitoring with production-grade features including distributed storage, automated SSL, load balancing, and namespace isolation.

## Architecture

![K3s Homelab Architecture](diagrams/architecture.svg)

## Service Endpoints

![Network Endpoints](diagrams/network-endpoints.svg)

## Key Features

### Infrastructure Components

- **K3s v1.28.5**: Lightweight Kubernetes distribution
- **Rancher**: Kubernetes management platform
- **Traefik**: Ingress controller with automatic SSL
- **MetalLB**: LoadBalancer for bare metal (192.168.11.200-250)
- **Longhorn**: Distributed block storage with 3-way replication
- **Cert-Manager**: Automated Let's Encrypt certificates via Cloudflare DNS
- **Sealed Secrets**: GitOps-friendly encrypted secrets
- **Prometheus Stack**: Metrics collection and alerting
- **Grafana**: Monitoring dashboards

### Namespace Organization

| Namespace | Purpose | Key Applications |
|-----------|---------|-----------------|
| `default` | Legacy media & network services | Overseerr, Calibre, Pi-hole, Zurg |
| `home-automation` | Smart home platform | Home Assistant, Zigbee2MQTT, Mosquitto, MariaDB |
| `network` | Network infrastructure | Unifi Controller, MongoDB |
| `monitoring` | Observability stack | Prometheus, Grafana, AlertManager |
| `longhorn-system` | Distributed storage | Longhorn components |
| `metallb-system` | Load balancing | MetalLB controller & speakers |
| `cert-manager` | Certificate management | Cert-Manager components |

### Storage Classes

| Storage Class | Purpose | Backend | Replication |
|--------------|---------|---------|------------|
| `longhorn` | Default distributed storage | Longhorn | 3-way |
| `longhorn-static` | Specific volume binding | Longhorn | 3-way |
| `longhorn-db-storage` | Database-optimized | Longhorn | 3-way |
| `nfs-books-csi` | Books/media storage | NFS | - |
| `nfs-downloads-csi` | Download storage | NFS | - |
| `smb` | SMB/CIFS storage | Network Share | - |

## Running Applications

### Home Automation (namespace: home-automation)
- **Home Assistant** (192.168.11.212) - Smart home platform with host networking
- **Zigbee2MQTT** (192.168.11.213) - Zigbee device bridge (pinned to homelab-03)
- **Mosquitto** (192.168.11.206) - MQTT broker
- **MariaDB** (192.168.11.203) - MySQL database for Home Assistant

### Media Management (namespace: default)
- **Overseerr** (192.168.11.202) - Media request management
- **Calibre** (192.168.11.209) - E-book library management
- **Calibre-Web** (192.168.11.210) - Web interface for Calibre
- **Calibre-Web Automated** (192.168.11.211) - Automated book processing
- **Zurg** (192.168.11.208) - Real-Debrid WebDAV server

### Network Services
- **Pi-hole** (192.168.11.222) - Network-wide ad blocking (namespace: default)
- **Unifi Controller** (192.168.11.205) - Network management (namespace: network)
- **phpMyAdmin** (192.168.11.204) - Database management (namespace: default)

### Monitoring (namespace: monitoring)
- **Prometheus** - Metrics collection and time-series database
- **Grafana** - Visualization and dashboards (ingress: grafana.erix-homelab.site)
- **AlertManager** - Alert routing and management
- **Node Exporter** - Hardware and OS metrics

### Infrastructure
- **Longhorn UI** (192.168.11.201) - Storage management dashboard
- **Traefik Dashboard** - Ingress routing and SSL management

## Deployment Methods

### 1. Direct kubectl Apply
```bash
kubectl apply -f <application-directory>/
```

### 2. Helm Chart Deployment
Using the standardized `homelab-app` chart:
```bash
helm install <app-name> ./helm/homelab-app -f ./helm/homelab-app/values/<app-name>.yaml
```

### 3. GitOps Ready
Repository structure supports ArgoCD (installed but not actively used).

## Quick Start

### Prerequisites
- K3s cluster up and running
- kubectl configured with cluster access
- Helm 3.x installed (optional)

### Deploy an Application

**Method 1: kubectl**
```bash
cd k3s/apps
kubectl apply -f <app-directory>/
```

**Method 2: Helm**
```bash
cd k3s
helm install myapp ./helm/homelab-app -f ./helm/homelab-app/values/myapp.yaml
```

### Common Operations

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check services and IPs
kubectl get svc -A | grep LoadBalancer

# View application logs
kubectl logs -f -n <namespace> <pod-name>

# Check ingress endpoints
kubectl get ingress -A

# Monitor deployments
kubectl get deployments -A

# Access Longhorn UI
open http://192.168.11.201

# Access Grafana
open https://grafana.erix-homelab.site

# Troubleshoot MetalLB
cd /path/to/k3s && ./metallb_logs.sh
```

## Cluster Nodes

| Node | IP | Role | Status | Specs | Notes |
|------|-------|------|--------|-------|-------|
| homelab-control | 192.168.11.11 | Control Plane, Master | Ready | Raspberry Pi, Debian 12 | 625 days uptime |
| homelab-02 | 192.168.11.12 | Worker | Ready | Raspberry Pi, Debian 12 | 129 days uptime |
| homelab-03 | 192.168.11.13 | Worker | Ready | Raspberry Pi, Debian 12 | 625 days uptime, USB Zigbee |
| homelab-04 | 192.168.11.14 | Worker | Ready | Raspberry Pi, Debian 12 | 129 days uptime, DB workloads |

**Runtime**: containerd 1.7.11-k3s2
**Kubernetes**: v1.28.5+k3s1
**OS**: Debian GNU/Linux 12 (Bookworm)
**Kernel**: 6.12.47+rpt-rpi-v8

## Repository Structure

```
k3s/apps/
├── README.md                    # This file
├── CLAUDE.md                    # Development documentation
├── helm/
│   ├── homelab-app/            # Standardized application chart
│   ├── homelab-common/         # Library chart for shared templates
│   └── home-assistant-stack/   # Multi-component stack chart
├── <app-name>/                 # Individual application manifests
│   ├── *-deployment.yaml       # Deployment or StatefulSet
│   ├── *-service.yaml          # Service definition
│   ├── *-ingress.yaml          # Ingress rules
│   └── *-pvc.yaml              # PersistentVolumeClaim
└── ansible/                    # Cluster management automation
```

## Networking

### External Access
All applications use `*.erix-homelab.site` domain with automatic SSL certificates via Traefik ingress controller and Cert-Manager (Let's Encrypt + Cloudflare DNS-01).

### Load Balancing
MetalLB provides LoadBalancer services from IP pool **192.168.11.200-250**.

### Ingress Routes
All ingress traffic flows through Traefik at 192.168.11.200 (ports 80/443) and routes to backend services based on hostname.

### Special Network Configurations
- **Host Networking**: Home Assistant uses host network mode for mDNS/device discovery
- **NodePort**: Pi-hole exposed via NodePort for DHCP functionality
- **Node Affinity**: Zigbee2MQTT pinned to homelab-03 for USB Zigbee stick access

## Storage Strategy

### Longhorn Distributed Storage
- **Replication**: 3-way replication across worker nodes
- **Snapshots**: Point-in-time snapshots for backup
- **Volume Types**: Standard, static, and database-optimized storage classes
- **UI**: Web interface at 192.168.11.201

### External Storage
- **NFS CSI**: Books, media, and download directories
- **SMB CSI**: Additional network share support via CIFS
- **Rclone**: Cloud storage integration with persistent DaemonSets

## Security

- **Sealed Secrets**: Encrypted secrets safe for Git storage
- **Cert-Manager**: Automated SSL certificate renewal
- **Cloudflare DNS-01**: DNS challenge for wildcard certificates
- **TLS Everywhere**: All ingress endpoints use HTTPS
- **Namespace Isolation**: Services organized by function

## Monitoring & Observability

- **Prometheus**: Metrics collection from all cluster components
- **Grafana**: Visualization dashboards at grafana.erix-homelab.site
- **AlertManager**: Alert routing and notification
- **Node Exporter**: Hardware and OS metrics from all nodes
- **Longhorn UI**: Storage performance and health monitoring
- **Rancher Dashboard**: Cluster-wide observability

## Documentation

- **[CLAUDE.md](CLAUDE.md)**: Comprehensive development guide, troubleshooting, and architecture details
- **[deploy_with_common.md](deploy_with_common.md)**: Helm chart usage and deployment patterns
- **[network-diagram.md](network-diagram.md)**: Detailed network architecture

## Future Enhancements

- [ ] Complete GitOps migration to ArgoCD
- [ ] Expand Prometheus metrics collection
- [ ] Add custom Grafana dashboards
- [ ] Implement network policies for pod security
- [ ] Automate backup and disaster recovery
- [ ] Add Velero for cluster backups
- [ ] Migrate remaining default namespace apps to dedicated namespaces

## Troubleshooting

### Common Commands
```bash
# Check pod status
kubectl get pods -A -o wide

# Describe failing pod
kubectl describe pod -n <namespace> <pod-name>

# View logs
kubectl logs -n <namespace> <pod-name> -f

# Check PVC status
kubectl get pvc -A

# Verify LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer

# Check ingress routes
kubectl get ingress -A

# MetalLB diagnostics
./metallb_logs.sh  # Creates metallb_report.tgz

# Longhorn volume status
kubectl get volumes -n longhorn-system
```

### Common Issues
1. **Pod stuck in Pending**: Check PVC binding and node resources
2. **LoadBalancer IP pending**: Verify MetalLB configuration and IP pool
3. **Ingress not reachable**: Check Traefik logs and ingress class
4. **Storage issues**: Review Longhorn UI for volume health

## Contributing

This is a personal homelab project. Feel free to:
- Open issues for questions or suggestions
- Submit PRs for improvements
- Use as inspiration for your own homelab

## License

MIT License - see LICENSE file for details

---

**Built with**: K3s, Longhorn, Traefik, MetalLB, Home Assistant, Prometheus, and Raspberry Pis.
