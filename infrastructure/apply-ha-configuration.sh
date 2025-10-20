#!/bin/bash
# Script to configure High Availability for critical infrastructure components
# Strategy: 2 replicas with hard anti-affinity across worker nodes
# This ensures 1 node can fail without service disruption

set -e

echo "=========================================="
echo "High Availability Configuration Script"
echo "=========================================="
echo ""
echo "Strategy: 2 replicas + hard anti-affinity"
echo "Tolerates: 1 node failure"
echo "Avoids: Overloading remaining nodes"
echo ""

# Function to apply hard anti-affinity to a deployment
apply_hard_antiaffinity() {
  local namespace=$1
  local deployment=$2
  local app_label=$3

  echo "Processing $namespace/$deployment..."

  kubectl get deployment $deployment -n $namespace -o json | \
    jq '.spec.template.spec.affinity.podAntiAffinity = {
      "requiredDuringSchedulingIgnoredDuringExecution": [{
        "labelSelector": {
          "matchExpressions": [{
            "key": "'$app_label'",
            "operator": "In",
            "values": ["'$deployment'"]
          }]
        },
        "topologyKey": "kubernetes.io/hostname"
      }]
    }' | \
    kubectl apply -f -
}

# Function to set Recreate strategy
set_recreate_strategy() {
  local namespace=$1
  local deployment=$2

  echo "  Setting Recreate strategy for $deployment..."
  kubectl patch deployment $deployment -n $namespace --type='json' -p='[
    {"op": "replace", "path": "/spec/strategy", "value": {"type": "Recreate"}}
  ]'
}

# Function to scale deployment
scale_deployment() {
  local namespace=$1
  local deployment=$2
  local replicas=$3

  echo "  Scaling $deployment to $replicas replicas..."
  kubectl scale deploy $deployment -n $namespace --replicas=$replicas
}

echo "=========================================="
echo "Phase 1: Longhorn CSI Controllers"
echo "=========================================="
echo ""

for deployment in csi-provisioner csi-attacher csi-resizer csi-snapshotter; do
  apply_hard_antiaffinity "longhorn-system" "$deployment" "app"
  set_recreate_strategy "longhorn-system" "$deployment"
  scale_deployment "longhorn-system" "$deployment" 2
  echo ""
done

echo "=========================================="
echo "Phase 2: CoreDNS (DNS Resolution)"
echo "=========================================="
echo ""

apply_hard_antiaffinity "kube-system" "coredns" "k8s-app"
set_recreate_strategy "kube-system" "coredns"
scale_deployment "kube-system" "coredns" 2
echo ""

echo "=========================================="
echo "Phase 3: Traefik (Ingress Controller)"
echo "=========================================="
echo ""

apply_hard_antiaffinity "kube-system" "traefik" "app.kubernetes.io/name"
set_recreate_strategy "kube-system" "traefik"
scale_deployment "kube-system" "traefik" 2
echo ""

echo "=========================================="
echo "Phase 4: MetalLB Controller (LoadBalancer)"
echo "=========================================="
echo ""

apply_hard_antiaffinity "metallb-system" "metallb-controller" "app"
set_recreate_strategy "metallb-system" "metallb-controller"
scale_deployment "metallb-system" "metallb-controller" 2
echo ""

# echo "=========================================="
# echo "Phase 5: cert-manager (Certificate Management)"
# echo "=========================================="
# echo ""
# echo "SKIPPED - Not critical, keeping at 1 replica"
# echo ""
#
# for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do
#   apply_hard_antiaffinity "cert-manager" "$deployment" "app.kubernetes.io/name"
#   set_recreate_strategy "cert-manager" "$deployment"
#   scale_deployment "cert-manager" "$deployment" 2
#   echo ""
# done

# echo "=========================================="
# echo "Phase 6: Monitoring Stack"
# echo "=========================================="
# echo ""
# echo "SKIPPED - Not critical, keeping at 1 replica"
# echo ""
#
# for deployment in prometheus-kube-prometheus-operator prometheus-kube-state-metrics prometheus-grafana; do
#   apply_hard_antiaffinity "monitoring" "$deployment" "app.kubernetes.io/name"
#   set_recreate_strategy "monitoring" "$deployment"
#   scale_deployment "monitoring" "$deployment" 2
#   echo ""
# done

# echo "=========================================="
# echo "Phase 7: Supporting Services"
# echo "=========================================="
# echo ""
# echo "SKIPPED - Not critical, keeping at 1 replica"
# echo ""
#
# apply_hard_antiaffinity "kube-system" "metrics-server" "k8s-app"
# set_recreate_strategy "kube-system" "metrics-server"
# scale_deployment "kube-system" "metrics-server" 2
# echo ""
#
# apply_hard_antiaffinity "kube-system" "sealed-secrets-controller" "app.kubernetes.io/name"
# set_recreate_strategy "kube-system" "sealed-secrets-controller"
# scale_deployment "kube-system" "sealed-secrets-controller" 2
# echo ""

echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "Waiting for pods to stabilize..."
sleep 10
echo ""

echo "=========================================="
echo "Verification"
echo "=========================================="
echo ""

echo "=== Longhorn CSI Controllers ==="
for deployment in csi-provisioner csi-attacher csi-resizer csi-snapshotter; do
  echo "$deployment:"
  kubectl get pods -n longhorn-system -l app=$deployment -o wide --no-headers | awk '{print "  "$1, "->", $7}'
done
echo ""

echo "=== Critical Infrastructure ==="
echo "CoreDNS:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide --no-headers | awk '{print "  "$1, "->", $7}'
echo ""

echo "Traefik:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide --no-headers | awk '{print "  "$1, "->", $7}'
echo ""

echo "MetalLB Controller:"
kubectl get pods -n metallb-system -l app=metallb,component=controller -o wide --no-headers | awk '{print "  "$1, "->", $7}'
echo ""

echo "=========================================="
echo "Pod Count Per Node"
echo "=========================================="
echo ""

for node in homelab-02 homelab-03 homelab-04; do
  count=$(kubectl get pods -A -o wide --field-selector spec.nodeName=$node --no-headers 2>/dev/null | wc -l | xargs)
  echo "$node: $count pods"
done
echo ""

echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""
echo "Tier 1 - Critical Infrastructure (CONFIGURED):"
echo "  ✓ Longhorn CSI Controllers (4 deployments): 2 replicas each"
echo "  ✓ CoreDNS: 2 replicas"
echo "  ✓ Traefik: 2 replicas"
echo "  ✓ MetalLB Controller: 2 replicas"
echo ""
echo "Configuration applied:"
echo "  ✓ Hard anti-affinity (no co-location)"
echo "  ✓ Recreate deployment strategy"
echo "  ✓ 2 replicas across different nodes"
echo ""
echo "Tier 2 & 3 (NOT CONFIGURED - Staying at 1 replica):"
echo "  • cert-manager components"
echo "  • Monitoring stack (Prometheus, Grafana, etc.)"
echo "  • Supporting services (metrics-server, sealed-secrets)"
echo ""
echo "Benefits:"
echo "  ✓ Survive 1 node failure without service interruption"
echo "  ✓ No overloading of remaining nodes during failures"
echo "  ✓ ~8 additional pods total (4 components × 1 extra replica)"
echo ""
echo "Important:"
echo "  • Re-run this script after Helm upgrades"
echo "  • See README.md for enabling Tier 2 & 3"
echo ""
