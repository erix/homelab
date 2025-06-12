# K3s Homelab Network Diagram

## Physical Network Topology

```mermaid
graph TB
    Internet[Internet] --> Router[Router/Gateway<br/>192.168.11.1]
    Router --> LAN[LAN Network<br/>192.168.11.0/24]
    
    LAN --> Control[homelab-control<br/>192.168.11.11<br/>Control Plane]
    LAN --> Node02[homelab-02<br/>192.168.11.12<br/>Worker - NotReady]
    LAN --> Node03[homelab-03<br/>192.168.11.13<br/>Worker]
    LAN --> Node04[homelab-04<br/>192.168.11.14<br/>Worker]
    
    LAN --> MetalLB[MetalLB IP Pool<br/>192.168.11.200-250]
    
    Control -.->|K3s Cluster Network<br/>10.42.0.0/16| ClusterNet[Cluster Network]
    Node02 -.-> ClusterNet
    Node03 -.-> ClusterNet
    Node04 -.-> ClusterNet
```

## Kubernetes Service Architecture

```mermaid
graph TB
    subgraph "External Access"
        Internet2[Internet]
        Router2[Router]
        Traefik[Traefik Ingress<br/>SSL/TLS + Cert-Manager]
    end
    
    subgraph "MetalLB LoadBalancer Services"
        HA[Home Assistant<br/>192.168.11.207:8123]
        Unifi[Unifi Controller<br/>192.168.11.205:8080/8443]
        Z2M[Zigbee2MQTT<br/>192.168.11.206:8080]
        Pihole[Pi-hole DNS<br/>192.168.11.222:53]
        Maria[MariaDB<br/>192.168.11.203:3306]
        Overseer[Overseerr<br/>192.168.11.202:5055]
        Calibre[Calibre<br/>192.168.11.209:8080]
        CalibreWeb[Calibre-Web<br/>192.168.11.210:8083]
        MQTT[Mosquitto MQTT<br/>192.168.11.230:8883]
        Zurg[Zurg<br/>192.168.11.208:9999]
    end
    
    subgraph "ClusterIP Services"
        Prowlarr[Prowlarr]
        Sonarr[Sonarr]
        RDT[RDT-Client]
        Readarr[Readarr]
        OpenWebUI[Open-WebUI]
        Flare[Flaresolverr]
    end
    
    Internet2 --> Router2
    Router2 --> Traefik
    Router2 --> HA
    Router2 --> Unifi
    Router2 --> Z2M
    Router2 --> Pihole
    Router2 --> Maria
    Router2 --> Overseer
    Router2 --> Calibre
    Router2 --> CalibreWeb
    Router2 --> MQTT
    Router2 --> Zurg
    
    Traefik --> Prowlarr
    Traefik --> Sonarr
    Traefik --> RDT
    Traefik --> Readarr
    Traefik --> OpenWebUI
    Traefik --> HA
    Traefik --> Z2M
    Traefik --> Calibre
    Traefik --> CalibreWeb
```

## Storage Architecture

```mermaid
graph TB
    subgraph "Longhorn Distributed Storage"
        subgraph "homelab-control"
            ControlStorage[Local Storage<br/>Longhorn Volume]
        end
        
        subgraph "homelab-02 (NotReady)"
            Node02Storage[Local Storage<br/>Longhorn Volume]
        end
        
        subgraph "homelab-03"
            Node03Storage[Local Storage<br/>Longhorn Volume]
        end
        
        subgraph "homelab-04"
            Node04Storage[Local Storage<br/>Longhorn Volume]
        end
        
        ControlStorage <-.->|Replication| Node03Storage
        ControlStorage <-.->|Replication| Node04Storage
        Node03Storage <-.->|Replication| Node04Storage
        Node02Storage -.->|Offline| Node03Storage
    end
    
    subgraph "Storage Classes"
        LonghornDefault[longhorn - default<br/>General purpose]
        LonghornStatic[longhorn-static<br/>Static binding]
        LonghornDB[longhorn-db-storage<br/>Database optimized]
        NFSBooks[nfs-books-csi<br/>Books/Media]
        NFSDownloads[nfs-downloads-csi<br/>Downloads]
        SMB[smb<br/>Network storage]
    end
    
    subgraph "Persistent Volume Claims"
        HAPVC[homeassistant-pvc<br/>10Gi]
        MariaPVC[mariadb-sts-pvc<br/>50Gi]
        MongoPVC[mongodb-pvc<br/>10Gi]
        MediaPVC[pvc-media-nfs<br/>10Gi]
        BooksPVC[pvc-books-nfs<br/>10Gi]
        DownloadsPVC[pvc-downloads-nfs<br/>10Gi]
    end
    
    LonghornStatic --> HAPVC
    LonghornStatic --> MariaPVC
    LonghornDefault --> MongoPVC
    NFSBooks --> BooksPVC
    NFSDownloads --> DownloadsPVC
```

## Pod Distribution Across Nodes

```mermaid
graph TB
    subgraph "homelab-control (192.168.11.11)"
        ControlPlane[K3s Control Plane<br/>Rancher Management]
        ControlLonghorn[Longhorn Storage]
    end
    
    subgraph "homelab-02 (192.168.11.12) - NotReady"
        HAStateful[Home Assistant<br/>StatefulSet<br/>Host Network]
        Prowlarr2[Prowlarr]
        Readarr2[Readarr]
        OpenWebUI2[Open-WebUI]
        Calibre2[Calibre]
        CalibreWeb2[Calibre-Web]
        Overseer2[Overseerr]
        Pihole2[Pi-hole]
        Mosquitto2[Mosquitto]
        RClone2[rclone DaemonSet]
    end
    
    subgraph "homelab-03 (192.168.11.13)"
        Z2MPod[Zigbee2MQTT<br/>USB Device Access]
        RClone3[rclone DaemonSet]
        Node03Longhorn[Longhorn Storage]
    end
    
    subgraph "homelab-04 (192.168.11.14)"
        MongoStateful[MongoDB<br/>StatefulSet]
        MariaStateful[MariaDB<br/>StatefulSet]
        FlaresolverrPod[Flaresolverr]
        RClone4[rclone DaemonSet]
        Node04Longhorn[Longhorn Storage]
    end
    
    ControlLonghorn <-.->|Replication| Node03Longhorn
    ControlLonghorn <-.->|Replication| Node04Longhorn
    Node03Longhorn <-.->|Replication| Node04Longhorn
```

## Network Data Flow

```mermaid
sequenceDiagram
    participant User
    participant Router
    participant Traefik
    participant MetalLB
    participant Service
    participant Pod
    participant Longhorn
    
    Note over User,Longhorn: External Access via Ingress
    User->>Router: HTTPS Request
    Router->>Traefik: Forward to Ingress
    Traefik->>Service: Route to ClusterIP
    Service->>Pod: Load balance
    Pod->>Longhorn: Read/Write data
    
    Note over User,Longhorn: Direct Access via LoadBalancer
    User->>Router: Direct service access
    Router->>MetalLB: Forward to LB IP
    MetalLB->>Service: Route to service
    Service->>Pod: Forward request
    Pod->>Longhorn: Persist data
```

## Key Components Summary

- **Cluster**: 4 Raspberry Pi nodes (1 control + 3 workers)
- **Storage**: Longhorn distributed storage with 3-way replication
- **Networking**: MetalLB for LoadBalancer IPs, Traefik for ingress
- **SSL**: Cert-Manager with Let's Encrypt + Cloudflare DNS
- **Media Stack**: Plex ecosystem with *arr applications
- **Home Automation**: Home Assistant + Zigbee2MQTT + MQTT broker
- **Database**: MariaDB and MongoDB for application data