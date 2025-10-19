#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Home Automation Stack - Safe Namespace Migration ==="
echo ""
echo -e "${GREEN}✓${NC} All PVs verified with 'Retain' policy - data is safe"
echo -e "${YELLOW}⚠${NC}  This will cause downtime while services are migrated"
echo ""

# Pre-flight checks
echo "=== Pre-flight Checks ==="

echo -n "1. Checking PV reclaim policies... "
for pv in homeassistant mariadb-sts mosquitto z2m; do
    policy=$(kubectl get pv $pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null || echo "MISSING")
    if [ "$policy" != "Retain" ]; then
        echo -e "${RED}FAILED${NC}"
        echo "PV $pv has policy '$policy' (expected 'Retain')"
        exit 1
    fi
done
echo -e "${GREEN}OK${NC}"

echo -n "2. Checking namespace exists... "
kubectl get namespace home-automation &>/dev/null || {
    echo -e "${RED}FAILED${NC}"
    echo "Namespace 'home-automation' does not exist. Create it first."
    exit 1
}
echo -e "${GREEN}OK${NC}"

echo -n "3. Checking current deployments... "
kubectl get statefulset homeassistant -n default &>/dev/null || echo -e "${YELLOW}homeassistant not found${NC}"
kubectl get statefulset mariadb -n default &>/dev/null || echo -e "${YELLOW}mariadb not found${NC}"
kubectl get deployment mosquitto -n default &>/dev/null || echo -e "${YELLOW}mosquitto not found${NC}"
kubectl get deployment z2m -n default &>/dev/null || echo -e "${YELLOW}z2m not found${NC}"
echo -e "${GREEN}OK${NC}"

echo -n "4. Checking sealed secret file... "
if [ ! -f "maria-db/mariadb-password-sealed.yaml" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "Sealed secret file not found: maria-db/mariadb-password-sealed.yaml"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

echo ""
echo "=== Migration Plan ==="
echo "Services to migrate: Home Assistant, MariaDB, Mosquitto, Zigbee2MQTT"
echo "Storage to rebind: 61Gi across 4 PVs"
echo "Estimated downtime: 5-10 minutes"
echo ""

# Confirmation
read -p "Proceed with migration? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Migration cancelled"
    exit 0
fi

echo ""
echo "=== Step 1: Scaling Down Services ==="
kubectl scale statefulset homeassistant -n default --replicas=0 2>/dev/null || echo "homeassistant already scaled or missing"
kubectl scale statefulset mariadb -n default --replicas=0 2>/dev/null || echo "mariadb already scaled or missing"
kubectl scale deployment mosquitto -n default --replicas=0 2>/dev/null || echo "mosquitto already scaled or missing"
kubectl scale deployment z2m -n default --replicas=0 2>/dev/null || echo "z2m already scaled or missing"

echo "Waiting for pods to terminate (30s)..."
sleep 30

echo ""
echo "=== Step 2: Deleting PVCs in Default Namespace ==="
kubectl delete pvc homeassistant-pvc -n default 2>/dev/null || echo "homeassistant-pvc already deleted"
kubectl delete pvc mariadb-sts-pvc -n default 2>/dev/null || echo "mariadb-sts-pvc already deleted"
kubectl delete pvc mosquitto-pvc -n default 2>/dev/null || echo "mosquitto-pvc already deleted"
kubectl delete pvc z2m-pvc -n default 2>/dev/null || echo "z2m-pvc already deleted"

echo "Waiting for PVCs to be fully removed (15s)..."
sleep 15

echo ""
echo "=== Step 3: Checking PV Status ==="
for pv in homeassistant mariadb-sts mosquitto z2m; do
    status=$(kubectl get pv $pv -o jsonpath='{.status.phase}')
    echo "  PV $pv: $status"
    if [ "$status" != "Released" ] && [ "$status" != "Available" ]; then
        echo -e "${YELLOW}  Warning: Expected 'Released' or 'Available', got '$status'${NC}"
    fi
done

echo ""
echo "=== Step 4: Updating PV ClaimRefs to New Namespace ==="
for pv in homeassistant mariadb-sts mosquitto z2m; do
    echo -n "  Patching PV $pv... "
    kubectl patch pv $pv -p '{"spec":{"claimRef":{"namespace":"home-automation"}}}' &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
done

echo ""
echo "=== Step 5: Applying MariaDB Sealed Secret in New Namespace ==="
kubectl apply -f maria-db/mariadb-password-sealed.yaml &>/dev/null && echo -e "${GREEN}Sealed secret applied${NC}" || echo -e "${RED}Sealed secret failed${NC}"

echo ""
echo "=== Step 6: Creating PVCs in New Namespace ==="

echo -n "  Creating homeassistant-pvc... "
cat <<EOF | kubectl apply -f - &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: homeassistant-pvc
  namespace: home-automation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-static
  volumeName: homeassistant
  resources:
    requests:
      storage: 10Gi
EOF

echo -n "  Creating mariadb-sts-pvc... "
cat <<EOF | kubectl apply -f - &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-sts-pvc
  namespace: home-automation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-static
  volumeName: mariadb-sts
  resources:
    requests:
      storage: 50Gi
EOF

echo -n "  Creating mosquitto-pvc... "
cat <<EOF | kubectl apply -f - &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mosquitto-pvc
  namespace: home-automation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-static
  volumeName: mosquitto
  resources:
    requests:
      storage: 500Mi
EOF

echo -n "  Creating z2m-pvc... "
cat <<EOF | kubectl apply -f - &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: z2m-pvc
  namespace: home-automation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-static
  volumeName: z2m
  resources:
    requests:
      storage: 500Mi
EOF

echo ""
echo "Waiting for PVCs to bind (15s)..."
sleep 15

echo "=== Step 7: Verifying PVC Binding ==="
all_bound=true
for pvc in homeassistant-pvc mariadb-sts-pvc mosquitto-pvc z2m-pvc; do
    status=$(kubectl get pvc $pvc -n home-automation -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$status" = "Bound" ]; then
        echo -e "  $pvc: ${GREEN}$status${NC}"
    else
        echo -e "  $pvc: ${RED}$status${NC}"
        all_bound=false
    fi
done

if [ "$all_bound" = false ]; then
    echo -e "${RED}ERROR: Not all PVCs are bound. Stopping migration.${NC}"
    echo "Check PVC and PV status manually before proceeding."
    exit 1
fi

echo ""
echo "=== Step 8: Deploying Resources to New Namespace ==="

echo -n "  Applying configs... "
kubectl apply -f mqtt/mqtt-config.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}WARNING${NC}"

echo -n "  Applying Home Assistant... "
kubectl apply -f home-assistant/ha-service.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f home-assistant/ha-deployment.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f home-assistant/ha-ingress.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f home-assistant/ha-filebrowser-ingress.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"

echo -n "  Applying MariaDB... "
kubectl apply -f maria-db/mariadb.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"

echo -n "  Applying Mosquitto... "
kubectl apply -f mqtt/mqtt-deployment.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f mqtt/mqtt-service.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"

echo -n "  Applying Zigbee2MQTT... "
kubectl apply -f zigbee2mqtt/z2m-deployment.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f zigbee2mqtt/z2m-service.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"
kubectl apply -f zigbee2mqtt/z2m-ingress.yaml &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}"

echo ""
echo "=== Step 9: Waiting for Services to Start ==="
echo "This may take 2-5 minutes..."
echo ""

sleep 10
kubectl get pods -n home-automation

echo ""
echo "=== Migration Complete! ==="
echo ""
echo "Next steps:"
echo "1. Verify services are running: kubectl get pods -n home-automation"
echo "2. Check Home Assistant: https://hass.erix-homelab.site"
echo "3. Check Zigbee2MQTT: https://z2m.erix-homelab.site"
echo ""
echo "After verifying everything works, clean up old resources:"
echo "  kubectl delete statefulset homeassistant mariadb -n default"
echo "  kubectl delete deployment mosquitto z2m -n default"
echo "  kubectl delete svc homeassistant-service mariadb-service mosquitto-service z2m-service -n default"
echo "  kubectl delete ingress homeassistant-ingress homeassistant-filebrowser-ingress z2m-ingress -n default"
echo "  kubectl delete secret mariadb-password -n default"
echo "  kubectl delete configmap mosquitto-config -n default"
