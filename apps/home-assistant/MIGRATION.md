# Home Automation Stack - Namespace Migration Guide

## Overview

This guide explains how to migrate Home Assistant, Mosquitto, Zigbee2MQTT, and MariaDB from the `default` namespace to the dedicated `home-automation` namespace.

## Why This Migration is Safe

✅ **No Data Loss**: All PersistentVolumes have `Retain` policy
✅ **No Export/Import**: PVs are simply rebound to the new namespace
✅ **No Downtime Risk**: Services are cleanly shut down before migration
✅ **Reversible**: Can rollback if needed

## What Gets Migrated

### Services
- Home Assistant (StatefulSet with Samba sidecar)
- MariaDB (StatefulSet)
- Mosquitto MQTT Broker (Deployment)
- Zigbee2MQTT (Deployment)

### Storage (10Gi + 50Gi + 500Mi + 500Mi = ~61Gi total)
- `homeassistant-pvc` → `homeassistant` PV (10Gi)
- `mariadb-sts-pvc` → `mariadb-sts` PV (50Gi)
- `mosquitto-pvc` → `mosquitto` PV (500Mi)
- `z2m-pvc` → `z2m` PV (500Mi)

### Network Services
- LoadBalancer IPs preserved:
  - Home Assistant: 192.168.11.207 (ports 8123, 139, 445)
  - MariaDB: 192.168.11.203 (port 3306)
  - Mosquitto: 192.168.11.230 (port 8883)
  - Zigbee2MQTT: 192.168.11.206 (port 8080)

### Ingresses
- hass.erix-homelab.site
- ha-config.erix-homelab.site
- z2m.erix-homelab.site

## Migration Process

### Automated Migration (Recommended)

Run the migration script:

```bash
cd /Users/eriksimko/github/homelab/k3s/apps
./home-assistant/migrate-to-namespace.sh
```

The script will:
1. Scale down all deployments gracefully
2. Delete PVCs (PVs are retained)
3. Update PV references to new namespace
4. Create new PVCs in `home-automation` namespace
5. Apply all resources to new namespace
6. Wait for pods to be ready
7. Display cleanup commands

### Manual Migration Steps

If you prefer manual control:

```bash
# 1. Scale down deployments
kubectl scale statefulset homeassistant -n default --replicas=0
kubectl scale statefulset mariadb -n default --replicas=0
kubectl scale deployment mosquitto -n default --replicas=0
kubectl scale deployment z2m -n default --replicas=0

# 2. Delete old PVCs (PVs retained)
kubectl delete pvc homeassistant-pvc mariadb-sts-pvc mosquitto-pvc z2m-pvc -n default

# 3. Update PV claimRefs
kubectl patch pv homeassistant -p '{"spec":{"claimRef":{"namespace":"home-automation"}}}'
kubectl patch pv mariadb-sts -p '{"spec":{"claimRef":{"namespace":"home-automation"}}}'
kubectl patch pv mosquitto -p '{"spec":{"claimRef":{"namespace":"home-automation"}}}'
kubectl patch pv z2m -p '{"spec":{"claimRef":{"namespace":"home-automation"}}}'

# 4. Apply new resources
kubectl apply -f maria-db/mariadb-password-sealed.yaml
kubectl apply -f mqtt/mqtt-config.yaml
kubectl apply -f home-assistant/ha-deployment.yaml
kubectl apply -f home-assistant/ha-service.yaml
kubectl apply -f home-assistant/ha-ingress.yaml
kubectl apply -f home-assistant/ha-filebrowser-ingress.yaml
kubectl apply -f maria-db/mariadb.yaml
kubectl apply -f mqtt/mqtt-deployment.yaml
kubectl apply -f mqtt/mqtt-service.yaml
kubectl apply -f zigbee2mqtt/z2m-deployment.yaml
kubectl apply -f zigbee2mqtt/z2m-service.yaml
kubectl apply -f zigbee2mqtt/z2m-ingress.yaml

# 5. Verify
kubectl get all -n home-automation
kubectl get pvc -n home-automation
kubectl get ingress -n home-automation
```

## Post-Migration Verification

### Check All Pods Are Running
```bash
kubectl get pods -n home-automation
```

Expected output:
```
NAME              READY   STATUS    RESTARTS   AGE
homeassistant-0   2/2     Running   0          5m
mariadb-0         1/1     Running   0          5m
mosquitto-xxx     1/1     Running   0          5m
z2m-xxx           1/1     Running   0          5m
```

### Check Services and LoadBalancers
```bash
kubectl get svc -n home-automation
```

Verify LoadBalancer IPs are assigned correctly.

### Check Ingresses
```bash
kubectl get ingress -n home-automation
```

### Test Connectivity
- Home Assistant: https://hass.erix-homelab.site
- Zigbee2MQTT: https://z2m.erix-homelab.site
- Grafana: https://grafana.erix-homelab.site

### Check Home Assistant Logs
```bash
kubectl logs -f homeassistant-0 -c homeassistant -n home-automation
```

## Cleanup Old Resources

After verifying everything works:

```bash
# Delete old deployments/statefulsets
kubectl delete statefulset homeassistant -n default
kubectl delete statefulset mariadb -n default
kubectl delete deployment mosquitto -n default
kubectl delete deployment z2m -n default

# Delete old services
kubectl delete svc homeassistant-service mariadb-service mosquitto-service z2m-service -n default

# Delete old ingresses
kubectl delete ingress homeassistant-ingress homeassistant-filebrowser-ingress z2m-ingress -n default

# Delete old secrets/configs (if they exist in default)
kubectl delete secret mariadb-password -n default --ignore-not-found
kubectl delete configmap mosquitto-config -n default --ignore-not-found
```

## Important Notes

### Sealed Secret
The MariaDB sealed secret has been updated to target the `home-automation` namespace. If the sealed secret fails to decrypt:

```bash
# Get the original password from the old secret
kubectl get secret mariadb-password -n default -o jsonpath='{.data.rootPassword}' | base64 -d

# Create new secret in home-automation namespace
kubectl create secret generic mariadb-password \
  -n home-automation \
  --from-literal=rootPassword='YOUR_PASSWORD' \
  --from-literal=dbPassword='YOUR_DB_PASSWORD' \
  --dry-run=client -o yaml | kubeseal -o yaml > maria-db/mariadb-password-sealed.yaml

# Apply new sealed secret
kubectl apply -f maria-db/mariadb-password-sealed.yaml
```

### Zigbee2MQTT Configuration
The MQTT server URL has been updated from:
- Old: `mqtt://mosquitto-service.default.svc.cluster.local:8883`
- New: `mqtt://mosquitto-service.home-automation.svc.cluster.local:8883`

### Node Affinity
- Zigbee2MQTT must run on `homelab-03` (USB device access)
- MariaDB prefers `homelab-04` (database node)

## Rollback Procedure

If something goes wrong:

```bash
# 1. Scale down new deployments
kubectl scale statefulset homeassistant -n home-automation --replicas=0
kubectl scale statefulset mariadb -n home-automation --replicas=0
kubectl scale deployment mosquitto -n home-automation --replicas=0
kubectl scale deployment z2m -n home-automation --replicas=0

# 2. Update PV claimRefs back to default
kubectl patch pv homeassistant -p '{"spec":{"claimRef":{"namespace":"default"}}}'
kubectl patch pv mariadb-sts -p '{"spec":{"claimRef":{"namespace":"default"}}}'
kubectl patch pv mosquitto -p '{"spec":{"claimRef":{"namespace":"default"}}}'
kubectl patch pv z2m -p '{"spec":{"claimRef":{"namespace":"default"}}}'

# 3. Recreate PVCs in default namespace
# (Use original PVC definitions with namespace: default)

# 4. Scale up old deployments
kubectl scale statefulset homeassistant -n default --replicas=1
kubectl scale statefulset mariadb -n default --replicas=1
kubectl scale deployment mosquitto -n default --replicas=1
kubectl scale deployment z2m -n default --replicas=1
```

## Files Updated

All manifests have been updated with `namespace: home-automation`:

- `home-assistant/namespace.yaml` (new)
- `home-assistant/ha-deployment.yaml`
- `home-assistant/ha-service.yaml`
- `home-assistant/ha-ingress.yaml`
- `home-assistant/ha-filebrowser-ingress.yaml`
- `mqtt/mqtt-deployment.yaml`
- `mqtt/mqtt-service.yaml`
- `mqtt/mqtt-config.yaml`
- `zigbee2mqtt/z2m-deployment.yaml`
- `zigbee2mqtt/z2m-service.yaml`
- `zigbee2mqtt/z2m-ingress.yaml`
- `maria-db/mariadb.yaml`
- `maria-db/mariadb-pvc.yaml`
- `maria-db/mariadb-password-sealed.yaml`

## Support

If you encounter issues:
1. Check pod logs: `kubectl logs <pod-name> -n home-automation`
2. Check events: `kubectl get events -n home-automation --sort-by='.lastTimestamp'`
3. Verify PVC binding: `kubectl get pvc -n home-automation`
4. Check PV status: `kubectl get pv | grep -E "(homeassistant|mosquitto|z2m|mariadb)"`
