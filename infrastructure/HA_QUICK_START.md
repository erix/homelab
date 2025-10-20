# High Availability Quick Start Guide

## TL;DR

Run one script to configure HA for all critical infrastructure:

```bash
cd /Users/eriksimko/github/homelab/k3s/apps/infrastructure
./apply-ha-configuration.sh
```

This gives you:
- ✅ 2 replicas for all critical components
- ✅ Hard anti-affinity (no 2 pods on same node)
- ✅ Survive 1 node failure without service interruption

## What Gets Configured

### Before
- Most components: 1 replica (single point of failure)
- Longhorn CSI: 3 replicas (overload risk during node failure)

### After
- All critical components: 2 replicas
- Hard anti-affinity: Always on different nodes
- When 1 node fails: Services stay up on remaining 2 nodes

## Components (Total: 7 Deployments - Tier 1 Only)

**Critical Infrastructure:**
- CoreDNS (DNS resolution)
- Traefik (Ingress controller)
- MetalLB Controller (LoadBalancer IP management)

**Storage:**
- Longhorn CSI: csi-provisioner, csi-attacher, csi-resizer, csi-snapshotter

**Not Configured (Tier 2 & 3):**
- cert-manager, monitoring stack, supporting services remain at 1 replica

## When to Re-run

After upgrading via Helm:
- Longhorn
- Traefik (if managed via Helm)
- K3s (CoreDNS is bundled with K3s)

Just run the script again after any Helm upgrade:
```bash
./apply-ha-configuration.sh
```

## Expected Impact

### Resource Usage
- ~7 additional pods across your cluster (7 components × 1 extra replica)
- Distributed across 3 nodes: ~2-3 extra pods per node
- Current alert threshold: 25 pods per node
- homelab-03 should go from 33 → ~26 pods (under threshold!)

### Node Failure Tolerance
**Before:**
- 1 node fails → Single-replica services go down → **Outages**

**After:**
- 1 node fails → All services have 2nd replica on other node → **No outages**

## Quick Verification

Check that components have 2/2 replicas:
```bash
kubectl get deploy -A | grep -E "coredns|traefik|metallb-controller|cert-manager|csi-"
```

Check pod distribution across nodes:
```bash
for node in homelab-02 homelab-03 homelab-04; do
  count=$(kubectl get pods -A -o wide --field-selector spec.nodeName=$node --no-headers | wc -l | xargs)
  echo "$node: $count pods"
done
```

## Troubleshooting

**Pods stuck in Pending?**
```bash
kubectl get pods -A | grep Pending
kubectl describe pod <pod-name> -n <namespace>
```

If you see "didn't match pod anti-affinity rules":
- This is expected if a node is down
- Hard anti-affinity is working correctly
- Pods will schedule when node recovers

**Want more details?**
See the full README.md in this directory.

## Philosophy

> "Better to have 2 replicas always available than 3 replicas that overload nodes during failures."

With 3 worker nodes:
- **2 replicas** = Always maintains availability during 1 node failure
- **3 replicas** = Causes overload or reduced availability during 1 node failure

## Next Steps After Running Script

1. Monitor your Telegram alerts for pod count changes
2. Verify no single node exceeds 30 pods
3. Test failover by cordoning a node and watching pod redistribution
4. Update your runbooks to include re-running this script after Helm upgrades

## Questions?

Check the detailed documentation:
- **README.md** - Full HA configuration guide (this directory)
- **longhorn/README.md** - Longhorn-specific details
- **CLAUDE.md** - Overall homelab architecture (repository root)
