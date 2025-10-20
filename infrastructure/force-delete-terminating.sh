#!/bin/bash
# Force delete all Terminating pods on a NotReady node
# Usage: ./force-delete-terminating.sh homelab-02

set -e

NODE=$1

if [ -z "$NODE" ]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi

echo "🔍 Finding Terminating pods on $NODE..."

# Get all terminating pods on the specified node
TERMINATING_PODS=$(kubectl get pods -A \
  --field-selector spec.nodeName=$NODE \
  -o json | \
  jq -r '.items[] | select(.metadata.deletionTimestamp != null) |
    "\(.metadata.namespace) \(.metadata.name)"')

if [ -z "$TERMINATING_PODS" ]; then
  echo "✅ No terminating pods found on $NODE"
  exit 0
fi

echo "Found terminating pods:"
echo "$TERMINATING_PODS"
echo ""
read -p "Force delete these pods? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted"
  exit 0
fi

echo "🗑️  Force deleting pods..."

while IFS= read -r line; do
  namespace=$(echo $line | awk '{print $1}')
  pod=$(echo $line | awk '{print $2}')

  echo "  Deleting $namespace/$pod..."
  kubectl delete pod -n $namespace $pod --grace-period=0 --force
done <<< "$TERMINATING_PODS"

echo "✅ Done! Check node status with: kubectl get nodes"
