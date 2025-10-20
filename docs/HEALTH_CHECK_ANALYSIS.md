# Health Check Analysis - Cluster Stability Issues

**Date**: 2025-10-20
**Issue**: Multiple components experiencing frequent restarts due to aggressive liveness probe timeouts

## Problem Summary

Several critical infrastructure components are configured with 1-second liveness probe timeouts, which is too aggressive for Raspberry Pi ARM hardware. Under system load, these components cannot respond within 1 second, causing Kubernetes to kill and restart containers unnecessarily.

## Components Affected

### Critical (High Restart Counts)

| Component | Namespace | Restarts | Timeout | Failures | Total Grace |
|-----------|-----------|----------|---------|----------|-------------|
| **prometheus-node-exporter** (homelab-03) | monitoring | **7,444** | 1s | 3 | 3s |
| **prometheus-node-exporter** (homelab-02) | monitoring | **455** | 1s | 3 | 3s |
| **prometheus-node-exporter** (homelab-04) | monitoring | **160** | 1s | 3 | 3s |
| **csi-smb-node** (homelab-03) | kube-system | **698** | likely 1s | - | - |
| **csi-nfs-node** (homelab-03) | kube-system | **642** | likely 1s | - | - |
| **csi-nfs-node** (homelab-02) | kube-system | **102** | likely 1s | - | - |
| **csi-smb-node** (homelab-02) | kube-system | **132** | likely 1s | - | - |
| **engine-image** (homelab-02) | longhorn-system | **556** | likely 1s | - | - |

### Moderate Risk (1s Timeout, Low Restarts So Far)

| Component | Namespace | Timeout | Failures | Total Grace |
|-----------|-----------|---------|----------|-------------|
| **CoreDNS** | kube-system | 1s | 3 | 3s |
| **metrics-server** | kube-system | 1s | 3 | 3s |
| **cert-manager-webhook** | cert-manager | 1s | 3 | 3s |
| **sealed-secrets-controller** | kube-system | 1s | 3 | 3s |
| **prometheus-operator** | monitoring | 1s | 3 | 3s |
| **metallb-controller** | metallb-system | 1s | 3 | 3s |
| **capi-controller-manager** | cattle-provisioning-capi-system | 1s | 3 | 3s |

## Root Cause

**The 1-second timeout is insufficient for ARM hardware**, especially when:
- System is under load (CPU/memory pressure)
- Storage I/O is occurring (especially on SD cards or networked storage)
- Multiple probes are being checked simultaneously across the cluster
- Network latency spikes occur

## Impact Analysis

### homelab-03 (Most Affected)
- Node-exporter: 7,444 restarts
- CSI drivers experiencing high restart counts
- This node appears to be under the most stress

### homelab-02 (Moderate Impact)
- Node-exporter: 455 restarts
- CSI drivers and Longhorn components affected
- Likely correlated with database and stateful workloads

### homelab-04 (Lower Impact)
- Node-exporter: 160 restarts
- Dedicated to database workloads with nodeSelector
- More stable, but still affected

## Recommended Actions

### Priority 1: Fix Prometheus Node Exporter (CRITICAL)
The node-exporter is experiencing catastrophic restart counts. This affects monitoring and metrics collection.

**Fix**: Update `prometheus` Helm values to increase probe timeouts

### Priority 2: Review CSI Driver Health Checks
CSI drivers (NFS, SMB) are critical for storage operations and experiencing significant instability.

**Fix**: Check CSI driver configurations and increase timeouts if possible

### Priority 3: Update Core Infrastructure Components
CoreDNS, metrics-server, cert-manager are foundational components that should be stable.

**Fix**: Patch or update configurations to increase probe resilience

### Priority 4: Review Node Resource Allocation
homelab-03 shows significantly higher restart counts, suggesting resource contention.

**Fix**: Investigate node resource usage and consider rebalancing workloads

## Standard Recommended Settings for ARM Hardware

Based on the MetalLB fix that resolved speaker restarts:

```yaml
livenessProbe:
  enabled: true
  timeoutSeconds: 5        # 1s → 5s (5x more time)
  failureThreshold: 5      # 3 → 5 (more tolerance)
  periodSeconds: 15        # 10s → 15s (less frequent checks)
  initialDelaySeconds: 10  # Keep or increase
  successThreshold: 1      # Keep default

readinessProbe:
  enabled: true
  timeoutSeconds: 5        # 1s → 5s
  failureThreshold: 3      # Keep at 3 for faster detection
  periodSeconds: 10        # Keep at 10s for readiness
  initialDelaySeconds: 10  # Keep or increase
  successThreshold: 1      # Keep default
```

**Total grace period**: 5 failures × 5s timeout = **25 seconds** (vs current 3s)

## Next Steps

1. ✅ **MetalLB speaker** - FIXED (applied 2025-10-20)
2. ⏳ **Prometheus node-exporter** - IN PROGRESS
3. ⏳ **CSI drivers** (NFS, SMB) - NEEDS INVESTIGATION
4. ⏳ **Core infrastructure** (CoreDNS, metrics-server, cert-manager) - PLANNED
5. ⏳ **Node resource analysis** - PLANNED

## Monitoring

After applying fixes, monitor for:

```bash
# Check restart counts (should stabilize)
kubectl get pods -A -o wide | grep -v "0/.*Running" | awk '{if ($4 > 5) print $0}'

# Watch for liveness probe failures
kubectl get events -A --watch | grep -i "liveness"

# Check node resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu
```

## Files Created

- `metallb/values.yaml` - MetalLB health check fixes
- `metallb/README.md` - MetalLB documentation
- `prometheus/health-check-values.yaml` - Prometheus fixes (to be created)
- This analysis document

## References

- [Kubernetes Liveness/Readiness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [MetalLB Health Check Fix](metallb/README.md)
- Prometheus: `helm show values prometheus-community/kube-prometheus-stack`
