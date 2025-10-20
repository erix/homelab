# Longhorn CSI Controller Configuration

## Overview

The Longhorn CSI controllers have been configured with **hard anti-affinity** to ensure that no two replicas of the same controller run on the same node. This configuration prioritizes avoiding pod co-location over maintaining full replica counts during node failures.

## Current Configuration

### Anti-Affinity Rules

All four CSI controllers use hard anti-affinity:
- **csi-provisioner** (2 replicas)
- **csi-attacher** (2 replicas)
- **csi-resizer** (2 replicas)
- **csi-snapshotter** (2 replicas)

### Deployment Strategy

All CSI controllers use `Recreate` strategy instead of `RollingUpdate` to prevent conflicts during updates when hard anti-affinity is enabled.

### Expected Distribution

With 3 worker nodes (homelab-02, homelab-03, homelab-04), each CSI controller should have:
- **2 replicas across 2 different nodes** when all nodes are healthy
- **1 replica** if the node hosting a replica goes down
- **Automatic scheduling** to a different node when the failed node recovers (will pick an available node without a replica)

## Behavior During Node Failures

### Scenario: One Node Goes Down

1. Pod on failed node becomes unavailable
2. Kubernetes attempts to reschedule the pod
3. Pod can reschedule on the 3rd node (which doesn't have a replica)
4. System maintains **2/2 replicas** on the remaining healthy nodes
5. Storage operations continue normally (full availability maintained)

### Scenario: Node Recovers

1. When the failed node recovers, 2 replicas are already running on the other nodes
2. Hard anti-affinity keeps the current distribution stable
3. If you want to rebalance, you can manually delete one pod to force it to reschedule on the recovered node
4. Normal operations: No rebalancing needed - 2 replicas across any 2 nodes is sufficient

## Post-Upgrade Maintenance

### When to Reapply Configuration

You **MUST** reapply the CSI controller configuration after:
- Longhorn Helm chart upgrades
- Longhorn version updates
- Any changes to CSI controller deployments

### How to Reapply Configuration

Two scripts are provided for easy reapplication:

#### 1. Apply Hard Anti-Affinity

```bash
cd /Users/eriksimko/github/homelab/k3s/apps/longhorn
./apply-hard-antiaffinity.sh
```

This script:
- Adds `requiredDuringSchedulingIgnoredDuringExecution` to all CSI controllers
- Ensures no two replicas can run on the same node
- Displays the final distribution

#### 2. Fix Deployment Strategy

```bash
cd /Users/eriksimko/github/homelab/k3s/apps/longhorn
./fix-csi-deployment-strategy.sh
```

This script:
- Changes deployment strategy from `RollingUpdate` to `Recreate`
- Prevents pending pods during updates with hard anti-affinity

### Complete Post-Upgrade Procedure

After upgrading Longhorn via Helm:

```bash
# 1. Verify Longhorn upgrade completed successfully
helm list -n longhorn-system
kubectl get pods -n longhorn-system

# 2. Navigate to Longhorn directory
cd /Users/eriksimko/github/homelab/k3s/apps/longhorn

# 3. Apply hard anti-affinity
./apply-hard-antiaffinity.sh

# 4. Fix deployment strategy
./fix-csi-deployment-strategy.sh

# 5. Verify configuration
kubectl get deploy csi-provisioner -n longhorn-system -o yaml | grep -A10 "podAntiAffinity"
kubectl get deploy csi-provisioner -n longhorn-system -o yaml | grep "type: Recreate"

# 6. Check pod distribution
kubectl get pods -n longhorn-system -l app=csi-provisioner -o wide
kubectl get pods -n longhorn-system -l app=csi-attacher -o wide
kubectl get pods -n longhorn-system -l app=csi-resizer -o wide
kubectl get pods -n longhorn-system -l app=csi-snapshotter -o wide

# 7. Verify each node has exactly 1 replica of each controller
```

Expected output: Each CSI controller should show 3 pods, with 1 pod on each of homelab-02, homelab-03, and homelab-04.

## Verification Commands

### Check Anti-Affinity Configuration

```bash
# Check if hard anti-affinity is configured
kubectl get deploy csi-provisioner -n longhorn-system -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution}' | jq .
```

Expected output should show the anti-affinity rule with `topologyKey: kubernetes.io/hostname`

### Check Deployment Strategy

```bash
# Check deployment strategy
kubectl get deploy csi-provisioner -n longhorn-system -o jsonpath='{.spec.strategy.type}'
```

Expected output: `Recreate`

### Check Pod Distribution

```bash
# Count pods per node
for node in homelab-02 homelab-03 homelab-04; do
  echo "=== $node ==="
  kubectl get pods -n longhorn-system -o wide --field-selector spec.nodeName=$node | grep -E "csi-(provisioner|attacher|resizer|snapshotter)" | grep -v plugin | wc -l
done
```

Expected output: Each node should show `4` (1 of each CSI controller type)

### Check for Pending Pods

```bash
# Check if any CSI controller pods are pending due to anti-affinity
kubectl get pods -n longhorn-system --field-selector status.phase=Pending
```

Expected output: Should be empty. If there are pending CSI controller pods, it means:
- More than 3 replicas are configured (check deployment spec)
- A node might be unavailable or tainted
- Anti-affinity is working correctly (preventing co-location)

## Troubleshooting

### Issue: CSI Controller Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -n longhorn-system | grep csi
csi-provisioner-xxxxx   0/1   Pending
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n longhorn-system
```

Look for message: `didn't match pod anti-affinity rules`

**Resolution:**
This is expected behavior when:
1. A node is down and you have exactly 3 worker nodes
2. Deployment was scaled beyond the number of available nodes

Verify:
```bash
# Check how many worker nodes are ready
kubectl get nodes -l '!node-role.kubernetes.io/control-plane'

# Check deployment replica count
kubectl get deploy csi-provisioner -n longhorn-system -o jsonpath='{.spec.replicas}'
```

If replica count > number of worker nodes, scale down:
```bash
kubectl scale deploy csi-provisioner csi-attacher csi-resizer csi-snapshotter -n longhorn-system --replicas=3
```

### Issue: Uneven Distribution After Node Recovery

**Symptoms:**
After a node recovers, CSI controllers are not evenly distributed.

**Resolution:**
Delete pods on over-allocated nodes to trigger rescheduling:
```bash
# Check distribution first
kubectl get pods -n longhorn-system -l app=csi-provisioner -o wide

# If homelab-04 has 2 replicas and homelab-02 has 0, delete one from homelab-04
kubectl delete pod <pod-name-on-homelab-04> -n longhorn-system
```

The new pod will automatically schedule on the under-allocated node due to anti-affinity.

### Issue: Configuration Lost After Helm Upgrade

**Symptoms:**
After `helm upgrade longhorn`, CSI controllers revert to soft anti-affinity.

**Resolution:**
This is expected! Helm manages the deployments and will overwrite custom patches.

Run the post-upgrade procedure:
```bash
cd /Users/eriksimko/github/homelab/k3s/apps/longhorn
./apply-hard-antiaffinity.sh
./fix-csi-deployment-strategy.sh
```

## Files in This Directory

- **README.md** (this file) - Documentation and procedures
- **apply-hard-antiaffinity.sh** - Script to apply hard anti-affinity to CSI controllers
- **fix-csi-deployment-strategy.sh** - Script to set Recreate deployment strategy
- **csi-hard-antiaffinity-patch.yaml** - Reference patch template (not directly applied)
- **db-storage.yaml** - Database-optimized StorageClass definition
- **dummy-sc.yaml** - Additional StorageClass configurations

## Technical Details

### Hard vs Soft Anti-Affinity

**Soft Anti-Affinity** (`preferredDuringSchedulingIgnoredDuringExecution`):
- Scheduler **tries** to avoid co-location but can ignore the rule
- Maintains replica count even if it means running 2+ replicas on same node
- Default Longhorn behavior

**Hard Anti-Affinity** (`requiredDuringSchedulingIgnoredDuringExecution`):
- Scheduler **must** enforce the anti-affinity rule
- Pod stays Pending if rule cannot be satisfied
- Prioritizes distribution over availability
- Our current configuration

### Why Recreate Strategy?

When using `RollingUpdate` strategy with hard anti-affinity:
1. Kubernetes tries to create a new pod before terminating the old one
2. New pod cannot schedule (anti-affinity rule prevents 2 pods on same node)
3. Pod stays Pending indefinitely
4. Rolling update gets stuck

With `Recreate` strategy:
1. All old pods are terminated first
2. New pods can then schedule on any available node
3. Update completes successfully
4. Trade-off: Brief downtime during updates (acceptable for storage controllers)

## Additional Notes

- This configuration is **not stored** in Longhorn Helm values
- It is applied via **kubectl patch** after deployment
- Longhorn Helm chart does not expose anti-affinity settings for CSI controllers
- Future Longhorn versions may add native support for this configuration

## References

- Longhorn Documentation: https://longhorn.io/
- Kubernetes Pod Anti-Affinity: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity
- Longhorn CSI Driver Architecture: https://longhorn.io/docs/latest/concepts/#csi-driver
