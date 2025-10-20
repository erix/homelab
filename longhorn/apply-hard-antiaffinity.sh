#!/bin/bash
# Script to apply hard anti-affinity to Longhorn CSI controllers
# This ensures no 2 replicas run on the same node

echo "Applying hard anti-affinity to Longhorn CSI controllers..."

for deployment in csi-provisioner csi-attacher csi-resizer csi-snapshotter; do
  echo "Processing $deployment..."

  kubectl get deployment $deployment -n longhorn-system -o json | \
    jq '.spec.template.spec.affinity.podAntiAffinity = {
      "requiredDuringSchedulingIgnoredDuringExecution": [{
        "labelSelector": {
          "matchExpressions": [{
            "key": "app",
            "operator": "In",
            "values": ["'$deployment'"]
          }]
        },
        "topologyKey": "kubernetes.io/hostname"
      }]
    }' | \
    kubectl apply -f -
done

echo "Scaling CSI controllers to 2 replicas..."
kubectl scale deploy csi-provisioner csi-attacher csi-resizer csi-snapshotter -n longhorn-system --replicas=2

echo "Done! Verifying configuration..."
sleep 5

for deployment in csi-provisioner csi-attacher csi-resizer csi-snapshotter; do
  echo ""
  echo "=== $deployment distribution ==="
  kubectl get pods -n longhorn-system -l app=$deployment -o wide
done
