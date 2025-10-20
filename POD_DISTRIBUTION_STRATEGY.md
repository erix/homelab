# Pod Distribution Strategy

**Date**: 2025-10-20
**Problem**: Pods concentrate on single nodes during recovery, causing persistent overload

## The Problem

After cluster incidents (like homelab-02 NotReady), pods migrate to healthy nodes and stay there permanently. This creates:
- **Unbalanced load**: One node runs 36 pods, others run 12
- **Resource exhaustion**: Overloaded node has 4x CPU load (15.68 on 4-core system)
- **Cascading failures**: High concentration increases failure risk
- **Manual intervention required**: Must manually redistribute pods each time

## Root Cause

Kubernetes scheduler does NOT automatically rebalance pods. Once scheduled, pods stay on their node until:
1. Pod crashes/restarts
2. Manual deletion/rescheduling
3. Node failure

## Permanent Solution: Topology Spread Constraints

Add `topologySpreadConstraints` to all deployments to ensure automatic distribution.

### Two Approaches

#### Approach 1: Pod Topology Spread (Recommended)
Kubernetes automatically spreads pods evenly across nodes based on topology keys.

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1  # Allow max difference of 1 pod between nodes
      topologyKey: kubernetes.io/hostname  # Spread across nodes
      whenUnsatisfiable: ScheduleAnyway  # Soft constraint (prefer but not require)
      labelSelector:
        matchLabels:
          app: myapp
```

**Advantages**:
- Automatic spreading across nodes
- Works with any number of nodes
- Self-healing when nodes recover
- Soft constraint won't block scheduling

**Disadvantages**:
- Only affects NEW pods (need to restart existing pods to rebalance)

#### Approach 2: Pod Anti-Affinity
Prefer different nodes but don't require it.

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: myapp
            topologyKey: kubernetes.io/hostname
```

**Advantages**:
- Simple to understand
- Already used for Prometheus components

**Disadvantages**:
- Less sophisticated than topology spread
- Doesn't balance as evenly with multiple replicas

### Recommended Configuration

**For single-replica deployments** (most of your apps):
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: <app-name>
```

**For StatefulSets** (mariadb, mongodb, homeassistant):
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule  # Harder constraint for databases
    labelSelector:
      matchLabels:
        app: <app-name>
```

**For pods with node requirements** (z2m, homeassistant):
Keep existing `nodeSelector` or `nodeName` - topology spread won't override it.

## Implementation Plan

### Phase 1: Critical Applications (Immediate)
Apply topology spread to applications currently causing concentration on homelab-03:
- pihole
- calibre (3 deployments)
- mosquitto
- flaresolverr
- open-webui

### Phase 2: All Deployments (This Week)
Apply to remaining deployments:
- Media stack (sonarr, radarr, prowlarr, overseer, etc.)
- Infrastructure (traefik, metallb-controller, etc.)

### Phase 3: Infrastructure Components (Next Week)
Review and apply to system deployments:
- Longhorn components (where applicable)
- Cert-manager
- Sealed-secrets

## Application Method

### Option A: Patch Existing Deployments
```bash
kubectl patch deployment <name> -n <namespace> --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/topologySpreadConstraints",
    "value": [{
      "maxSkew": 1,
      "topologyKey": "kubernetes.io/hostname",
      "whenUnsatisfiable": "ScheduleAnyway",
      "labelSelector": {
        "matchLabels": {
          "app": "<app-name>"
        }
      }
    }]
  }
]'
```

### Option B: Update YAML Manifests
Edit deployment YAML files and add topology spread constraints, then:
```bash
kubectl apply -f <deployment>.yaml
```

### Option C: Use Helm Chart Template
If using homelab-app chart, add topology spread to default values:
```yaml
# helm/homelab-app/values.yaml
topologySpreadConstraints:
  enabled: true
  maxSkew: 1
  whenUnsatisfiable: ScheduleAnyway
```

## Rebalancing After Implementation

After adding topology spread constraints, pods won't move automatically. To rebalance:

### Graceful Rollout
```bash
# For each deployment
kubectl rollout restart deployment <name> -n <namespace>

# This triggers a rolling update, respecting topology spread
```

### Batch Rebalance Script
```bash
#!/bin/bash
# Restart all deployments on homelab-03 to trigger rebalancing

DEPLOYMENTS=$(kubectl get deployments -A -o json | \
  jq -r '.items[] | select(.status.replicas > 0) |
  "\(.metadata.namespace) \(.metadata.name)"')

while IFS= read -r line; do
  ns=$(echo $line | awk '{print $1}')
  name=$(echo $line | awk '{print $2}')

  echo "Restarting $ns/$name..."
  kubectl rollout restart deployment $name -n $ns

  # Wait between restarts to avoid overwhelming cluster
  sleep 10
done <<< "$DEPLOYMENTS"
```

## Monitoring Pod Distribution

### Check Current Distribution
```bash
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c | sort -rn
```

### Expected Result (3 worker nodes)
```
~15 homelab-02
~15 homelab-03
~15 homelab-04
```

### Alert on Imbalance
Add Prometheus alert:
```yaml
- alert: PodDistributionImbalanced
  expr: |
    max(count(kube_pod_info) by (node)) -
    min(count(kube_pod_info) by (node)) > 10
  for: 30m
  annotations:
    summary: "Pod distribution is imbalanced across nodes"
```

## Special Cases

### Pods That MUST Stay on Specific Nodes

**homeassistant** (homelab-03):
- Uses host networking at 192.168.11.13
- Keep `hostNetwork: true` and `nodeName: homelab-03`
- Topology spread won't override this

**z2m** (homelab-03):
- Requires USB device `/dev/ttyUSB0`
- Keep `nodeSelector: {kubernetes.io/hostname: homelab-03}`
- Topology spread won't override this

**mariadb/mongodb** (homelab-04):
- Currently pinned via `nodeSelector`
- Can remove nodeSelector and rely on topology spread instead
- Or keep pinned if you want databases on specific node

### DaemonSets
DaemonSets run on all nodes by definition:
- longhorn-manager
- longhorn-csi-plugin
- metallb-speaker
- prometheus-node-exporter

Don't add topology spread to DaemonSets - they already distribute automatically.

## Testing the Solution

### Before Changes
```bash
# Current distribution (example)
29 homelab-03
12 homelab-04
4 homelab-02
```

### After Implementation + Restart
```bash
# Expected distribution (balanced)
15 homelab-03
15 homelab-04
15 homelab-02
```

### Simulate Node Failure
```bash
# Drain a node
kubectl drain homelab-02 --ignore-daemonsets --delete-emptydir-data

# Pods should spread across homelab-03 and homelab-04

# Uncordon node
kubectl uncordon homelab-02

# Over time (as pods restart), distribution should rebalance
```

## Long-term Benefits

After implementing topology spread constraints:

1. **Automatic rebalancing**: When nodes recover, new pods prefer less-loaded nodes
2. **Fault tolerance**: Failure of one node impacts fewer applications
3. **Better resource utilization**: CPU/memory/IO spread across cluster
4. **Reduced manual intervention**: No need to manually redistribute pods
5. **Prevents cascading failures**: Load spikes contained to fewer nodes

## Files to Create/Modify

- `POD_DISTRIBUTION_STRATEGY.md` (this file) - Strategy documentation
- `apply-topology-spread.sh` - Automated patching script
- Individual deployment YAML files - Add topology spread constraints
- `PREVENTION_PLAN.md` - Add as medium-priority fix

## References

- [Kubernetes Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Pod Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)
- Our previous Prometheus anti-affinity implementation (prometheus/health-check-values.yaml:65-76)

## Next Steps

1. Create `apply-topology-spread.sh` script for batch application
2. Test on 2-3 deployments first (pihole, calibre, mosquitto)
3. Verify pods redistribute after rollout restart
4. Roll out to all deployments
5. Monitor distribution over 48 hours
6. Document results in this file
