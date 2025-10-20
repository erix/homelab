# Pod Distribution Fix - Implementation Summary

**Date**: 2025-10-20
**Issue**: 36 pods concentrated on homelab-03, causing load of 15-19 (4x capacity on 4-CPU system)

## Problem

After the homelab-02 crisis recovery, pods migrated to homelab-03 and stayed there permanently, causing:
- **Severe overload**: Load 19.22 on 4-CPU system (homelab-03)
- **Unbalanced distribution**: 25 pods on homelab-03, 15 on homelab-02, 8 on homelab-04
- **Risk of cascading failure**: High concentration increases failure risk
- **Manual intervention required**: Had to manually redistribute pods after every incident

## Root Cause

**Kubernetes does NOT automatically rebalance pods.** Once scheduled, pods stay on their node until:
1. Pod crashes/restarts
2. Manual deletion
3. Node failure

## Solution Implemented

### Topology Spread Constraints

Added `topologySpreadConstraints` to **ALL deployments and StatefulSets** to ensure automatic pod distribution across nodes.

**Configuration Applied:**
```yaml
topologySpreadConstraints:
  - maxSkew: 1  # Max difference of 1 pod between nodes
    topologyKey: kubernetes.io/hostname  # Spread across nodes
    whenUnsatisfiable: ScheduleAnyway  # Soft constraint (prefer but not require)
    labelSelector:
      matchLabels:
        app: <app-name>
```

### Components Configured

✅ **Deployments** (32 total):
- **Applications** (default namespace):
  - pihole, calibre, calibre-web, calibre-web-automated
  - flaresolverr, open-webui, filebot
  - sonarr, prowlarr, readarr, overseer, rdtclient, plex-debrid, kometa

- **Infrastructure**:
  - metallb-controller
  - cert-manager, cert-manager-webhook, cert-manager-cainjector
  - traefik, metrics-server, sealed-secrets-controller, coredns
  - csi-nfs-controller, csi-smb-controller

- **Longhorn**:
  - longhorn-ui, longhorn-driver-deployer
  - csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter

✅ **StatefulSets** (2 total):
- mariadb (home-automation)
- homeassistant (home-automation)

### Tools Created

1. **apply-topology-spread.sh** - Automated script to apply topology spread constraints
   - Modes: `patch` (add constraints), `restart` (trigger rebalancing), `all` (both)
   - Idempotent: Safe to run multiple times
   - Location: `/Users/eriksimko/github/homelab/k3s/apply-topology-spread.sh`

2. **POD_DISTRIBUTION_STRATEGY.md** - Comprehensive strategy document
   - Explains the problem and solution
   - Provides implementation guidance
   - Includes monitoring commands
   - Location: `/Users/eriksimko/github/homelab/k3s/apps/POD_DISTRIBUTION_STRATEGY.md`

## Current Status

**Topology Spread Constraints**: ✅ Applied to all deployments
**Pod Distribution**: ⚠️ Still unbalanced (existing pods haven't moved yet)
**homelab-03 Load**: ⚠️ Still high (19.22) - expected until pods restart

### Current Distribution
```
25 pods - homelab-03 (OVERLOADED)
15 pods - homelab-02
8 pods  - homelab-04
```

### Expected Distribution (after rebalancing)
```
~16 pods - homelab-03
~16 pods - homelab-02
~16 pods - homelab-04
```

## Next Steps - IMPORTANT

### Option 1: Wait for Natural Rebalancing (Passive)
**Recommended if cluster is stable and you can tolerate current load**

Pods will gradually redistribute as they naturally restart due to:
- Rolling updates
- Image pulls
- Probe failures
- Node maintenance

**Timeline**: Days to weeks

**Pros**:
- Zero disruption
- No manual intervention
- Safe

**Cons**:
- homelab-03 stays overloaded until pods restart
- Risk of failure if load causes cascading issues

### Option 2: Trigger Immediate Rebalancing (Active)
**Recommended to immediately fix the overload issue**

Use the script to restart all deployments, triggering topology-based rescheduling:

```bash
cd /Users/eriksimko/github/homelab/k3s
./apply-topology-spread.sh restart
```

This will:
1. Ask for confirmation
2. Perform rolling restarts of all deployments (one at a time)
3. Wait 5 seconds between restarts to avoid overwhelming cluster
4. Kubernetes will reschedule pods using topology spread constraints
5. Pods will distribute evenly across homelab-02, homelab-03, homelab-04

**Timeline**: 10-30 minutes

**Pros**:
- Immediate rebalancing
- Reduces homelab-03 load quickly
- Prevents potential cascading failure

**Cons**:
- Brief service interruption during pod restarts (rolling updates minimize this)
- May trigger some Longhorn volume operations
- Requires monitoring during execution

### Option 3: Selective Rebalancing (Hybrid)
**Recommended if you want to test first**

Restart only the heaviest pods currently on homelab-03:

```bash
# Restart critical overloaded apps
kubectl rollout restart deployment pihole -n default
kubectl rollout restart deployment calibre -n default
kubectl rollout restart deployment calibre-web -n default
kubectl rollout restart deployment calibre-web-automated -n default

# Wait and monitor
kubectl get pods -A -o wide | grep -E "homelab" | awk '{print $8}' | sort | uniq -c
```

**Timeline**: 5-10 minutes

**Pros**:
- Lower risk than full restart
- Tests topology spread on subset
- Provides immediate partial relief

**Cons**:
- Only partial rebalancing
- May need to restart more pods later

## Monitoring After Implementation

### Check Pod Distribution
```bash
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | grep -E "homelab" | sort | uniq -c | sort -rn
```

**Expected result**: ~16 pods per node (±2)

### Check Node Load
```bash
kubectl top nodes
# Or detailed:
for node in homelab-02 homelab-03 homelab-04; do
  echo "$node:";
  ssh $node "uptime";
done
```

**Expected result**: Load <8 on all nodes (2x CPU count)

### Monitor Pod Restarts
```bash
watch -n 5 'kubectl get pods -A -o wide'
```

**Expected**: Rolling restarts, all pods return to Running state

### Check for Issues
```bash
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

**Look for**: Scheduling errors, probe failures, volume attachment issues

## Success Criteria

After rebalancing (whichever option you choose):

✅ Pod distribution balanced (±2 pods per node)
✅ homelab-03 load drops below 8.0
✅ All pods in Running state
✅ No scheduling errors
✅ Future pod restarts automatically distribute evenly

## Long-term Benefits

Once fully implemented and rebalanced:

1. **Automatic distribution**: Future pods spread evenly across nodes
2. **Self-healing**: When nodes recover, new pods prefer less-loaded nodes
3. **Fault tolerance**: Failure of one node impacts fewer applications
4. **No manual intervention**: System self-balances over time
5. **Prevents cascading failures**: Load concentrated on one node less likely

## Troubleshooting

### If pods won't schedule after restart
- Check: `kubectl describe pod <pod-name>`
- Look for: "0/3 nodes are available" errors
- Fix: May need to adjust `whenUnsatisfiable: ScheduleAnyway` (already set)

### If distribution still unbalanced
- Verify topology spread: `kubectl get deployment <name> -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'`
- Check pod labels match selector
- Ensure pods have actually restarted (check AGE column)

### If homelab-03 load stays high
- Check which processes: `ssh homelab-03 "ps aux --sort=-%cpu | head -20"`
- Longhorn engines: May need time to detach volumes
- Image pulls: Large images may cause temporary load spikes

## Files Created/Modified

- `/Users/eriksimko/github/homelab/k3s/apply-topology-spread.sh` - Automation script
- `/Users/eriksimko/github/homelab/k3s/apps/POD_DISTRIBUTION_STRATEGY.md` - Strategy guide
- `/Users/eriksimko/github/homelab/k3s/apps/POD_DISTRIBUTION_FIX_SUMMARY.md` - This file
- All deployment/statefulset configurations (patched in-place via kubectl)

## Recommendation

**I recommend Option 2 (Immediate Rebalancing)** because:

1. homelab-03 load is **dangerously high** (19.22 on 4-CPU system)
2. High risk of triggering another cascading failure
3. The script does rolling restarts (minimal disruption)
4. You'll see immediate improvement
5. Validates that topology spread constraints work correctly

**To execute**:
```bash
cd /Users/eriksimko/github/homelab/k3s
./apply-topology-spread.sh restart
```

The script will ask for confirmation before proceeding.

## Alternative: If You Want to Wait

If you prefer Option 1 (wait for natural rebalancing):
- Monitor homelab-03 load every hour
- If load exceeds 25, consider force-rebalancing
- Document when pods naturally restart and rebalance
- Accept risk of potential cascading failure

Your choice depends on your risk tolerance and current availability requirements.
