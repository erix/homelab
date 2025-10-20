#!/bin/bash
# Fix CSI deployment strategy to prevent rolling update issues with hard anti-affinity

echo "Setting deployment strategy to Recreate for CSI controllers..."

for deployment in csi-provisioner csi-attacher csi-resizer csi-snapshotter; do
  echo "Processing $deployment..."

  kubectl patch deployment $deployment -n longhorn-system --type='json' -p='[
    {"op": "replace", "path": "/spec/strategy", "value": {"type": "Recreate"}}
  ]'
done

echo "Done! Deployment strategies updated to Recreate."
echo "This prevents rolling update conflicts with hard anti-affinity."
