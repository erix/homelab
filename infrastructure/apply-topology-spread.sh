#!/bin/bash
# Apply topology spread constraints to deployments
# This ensures pods automatically distribute across nodes

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Kubernetes Pod Distribution Fix ===${NC}"
echo "This script adds topology spread constraints to prevent pod concentration"
echo ""

# Function to get primary label for a deployment
get_app_label() {
  local namespace=$1
  local deployment=$2

  # Try common label patterns
  local label=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
  if [ -z "$label" ]; then
    label=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.template.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null)
  fi
  if [ -z "$label" ]; then
    # Fallback to deployment name
    label="$deployment"
  fi

  echo "$label"
}

# Function to apply topology spread to a deployment
apply_topology_spread() {
  local namespace=$1
  local deployment=$2
  local app_label=$3
  local max_skew=${4:-1}
  local when_unsatisfiable=${5:-ScheduleAnyway}

  echo -e "${YELLOW}Processing: ${namespace}/${deployment}${NC}"

  # Check if already has topology spread constraints
  has_topology=$(kubectl get deployment "$deployment" -n "$namespace" \
    -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' 2>/dev/null)

  if [ "$has_topology" != "null" ] && [ -n "$has_topology" ]; then
    echo -e "  ${GREEN}✓${NC} Already has topology spread constraints, skipping"
    return 0
  fi

  # Create the patch
  patch=$(cat <<EOF
[
  {
    "op": "add",
    "path": "/spec/template/spec/topologySpreadConstraints",
    "value": [
      {
        "maxSkew": ${max_skew},
        "topologyKey": "kubernetes.io/hostname",
        "whenUnsatisfiable": "${when_unsatisfiable}",
        "labelSelector": {
          "matchLabels": {
            "app": "${app_label}"
          }
        }
      }
    ]
  }
]
EOF
)

  # Apply the patch
  if kubectl patch deployment "$deployment" -n "$namespace" --type='json' -p "$patch" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Applied topology spread constraints (maxSkew=${max_skew}, app=${app_label})"
  else
    echo -e "  ${RED}✗${NC} Failed to patch deployment"
    return 1
  fi
}

# Function to restart deployment for rebalancing
restart_deployment() {
  local namespace=$1
  local deployment=$2

  echo -e "${YELLOW}Restarting: ${namespace}/${deployment}${NC}"

  if kubectl rollout restart deployment "$deployment" -n "$namespace" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Rollout restart initiated"
  else
    echo -e "  ${RED}✗${NC} Failed to restart deployment"
    return 1
  fi
}

# Main execution
MODE=${1:-patch}  # patch, restart, or all

if [ "$MODE" = "help" ] || [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
  echo "Usage: $0 [MODE]"
  echo ""
  echo "Modes:"
  echo "  patch     - Add topology spread constraints (default)"
  echo "  restart   - Restart deployments to trigger rebalancing"
  echo "  all       - Patch and restart"
  echo ""
  echo "Example:"
  echo "  $0 patch           # Add constraints only"
  echo "  $0 restart         # Restart deployments only"
  echo "  $0 all             # Add constraints and restart"
  exit 0
fi

# Define deployments to configure
# Format: "namespace deployment"
DEPLOYMENTS=(
  # Default namespace - applications
  "default pihole"
  "default calibre"
  "default calibre-web"
  "default calibre-web-automated"
  "default mosquitto"
  "default flaresolverr"
  "default open-webui"
  "default filebot"
  "default sonarr"
  "default radarr"
  "default prowlarr"
  "default readarr"
  "default overseer-depl"
  "default rdtclient-deployment"
  "default plex-debrid"
  "default kometa"

  # Home automation (exclude z2m - has nodeSelector)
  # Note: homeassistant uses hostNetwork, topology won't override

  # MetalLB
  "metallb-system metallb-controller"

  # Cert-manager
  "cert-manager cert-manager"
  "cert-manager cert-manager-webhook"
  "cert-manager cert-manager-cainjector"

  # Longhorn (select deployments only, not DaemonSets)
  "longhorn-system longhorn-ui"
  "longhorn-system longhorn-driver-deployer"
  "longhorn-system csi-attacher"
  "longhorn-system csi-provisioner"
  "longhorn-system csi-resizer"
  "longhorn-system csi-snapshotter"

  # Kube-system
  "kube-system traefik"
  "kube-system metrics-server"
  "kube-system sealed-secrets-controller"
  "kube-system coredns"
  "kube-system csi-nfs-controller"
  "kube-system csi-smb-controller"
)

echo -e "${GREEN}Found ${#DEPLOYMENTS[@]} deployments to configure${NC}"
echo ""

# Patch mode
if [ "$MODE" = "patch" ] || [ "$MODE" = "all" ]; then
  echo -e "${YELLOW}=== Phase 1: Adding Topology Spread Constraints ===${NC}"
  echo ""

  for deployment_info in "${DEPLOYMENTS[@]}"; do
    namespace=$(echo "$deployment_info" | awk '{print $1}')
    deployment=$(echo "$deployment_info" | awk '{print $2}')

    # Check if deployment exists
    if ! kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
      echo -e "${YELLOW}Skipping: ${namespace}/${deployment} (not found)${NC}"
      continue
    fi

    # Get app label
    app_label=$(get_app_label "$namespace" "$deployment")

    # Apply topology spread
    apply_topology_spread "$namespace" "$deployment" "$app_label" 1 "ScheduleAnyway"

    echo ""
  done

  echo -e "${GREEN}=== Topology Spread Constraints Applied ===${NC}"
  echo ""
fi

# Restart mode
if [ "$MODE" = "restart" ] || [ "$MODE" = "all" ]; then
  echo -e "${YELLOW}=== Phase 2: Restarting Deployments for Rebalancing ===${NC}"
  echo ""

  # Ask for confirmation
  read -p "This will restart all configured deployments. Continue? (yes/no): " confirm

  if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 0
  fi

  echo ""

  for deployment_info in "${DEPLOYMENTS[@]}"; do
    namespace=$(echo "$deployment_info" | awk '{print $1}')
    deployment=$(echo "$deployment_info" | awk '{print $2}')

    # Check if deployment exists
    if ! kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
      continue
    fi

    # Restart deployment
    restart_deployment "$namespace" "$deployment"

    # Wait between restarts to avoid overwhelming cluster
    echo "  Waiting 5 seconds before next restart..."
    sleep 5

    echo ""
  done

  echo -e "${GREEN}=== All Deployments Restarted ===${NC}"
  echo ""
fi

echo -e "${GREEN}=== Complete! ===${NC}"
echo ""
echo "Next steps:"
echo "1. Monitor pod distribution: kubectl get pods -A -o wide | awk '{print \$8}' | sort | uniq -c"
echo "2. Check node load: kubectl top nodes"
echo "3. Wait 10-15 minutes for all pods to stabilize"
echo ""
echo "Expected result: Pods evenly distributed across homelab-02, homelab-03, homelab-04"
