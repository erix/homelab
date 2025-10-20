# Health Check Fixes Applied

**Date**: 2025-10-20
**Issue**: Cluster instability caused by aggressive liveness probe timeouts on ARM hardware

## Summary

Multiple critical components were experiencing frequent restarts due to 1-second liveness probe timeouts that were too aggressive for Raspberry Pi ARM nodes. Under system load, these components couldn't respond within 1 second, causing Kubernetes to unnecessarily kill and restart containers.

## Root Cause

**Default probe configuration (too aggressive for ARM):**
```yaml
timeoutSeconds: 1
failureThreshold: 3
periodSeconds: 10
```
**Total grace period**: 3 failures × 1s = **3 seconds** before restart

This was insufficient when nodes were under CPU/memory/IO load.

## Fixes Applied

### ✅ 1. MetalLB Speaker (Fixed 2025-10-20 14:44)

**Problem:**
- homelab-02: 21 restarts
- homelab-03: 12 restarts
- homelab-04: 8 restarts
- First sign of cluster instability

**Solution:**
```bash
helm upgrade metallb metallb/metallb -n metallb-system -f metallb/values.yaml
```

**Result:**
- All speaker pods redeployed with new configuration
- Restart counts reset to 0
- Probe timeout: 1s → 5s
- Probe failures: 3 → 5
- Probe period: 10s → 15s
- **New grace period**: 25 seconds

**Files:**
- `metallb/values.yaml` - Configuration
- `metallb/README.md` - Documentation

---

### ✅ 2. Prometheus Node-Exporter (Fixed 2025-10-20 14:56)

**Problem:**
- **homelab-03: 7,444 restarts** (CATASTROPHIC)
- **homelab-02: 455 restarts**
- **homelab-04: 160 restarts**
- Metrics collection gaps
- Major contributor to cluster instability

**Solution:**
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus/current-values.yaml \
  -f prometheus/health-check-values.yaml
```

**Result:**
- All node-exporter pods redeployed
- Restart counts reset to 0
- All 3 pods (one per node) running stable
- Probe configuration verified:
  - Liveness: timeout=5s, failures=5, period=15s
  - Readiness: timeout=5s, failures=3, period=10s
- **New grace period**: 25 seconds (liveness), 15 seconds (readiness)

**Additional Components Fixed:**
- Prometheus Operator
- Prometheus Server
- Alertmanager
- Grafana (with 60s initial delay)
- Kube-state-metrics

**Files:**
- `prometheus/health-check-values.yaml` - Configuration
- `prometheus/current-values.yaml` - Backup of original values
- `prometheus/README.md` - Documentation

---

## Standard Configuration Applied

All fixed components now use these optimized settings for ARM hardware:

```yaml
livenessProbe:
  enabled: true
  timeoutSeconds: 5        # Was: 1s
  failureThreshold: 5      # Was: 3
  periodSeconds: 15        # Was: 10s
  initialDelaySeconds: 10  # Unchanged (60s for Grafana)
  successThreshold: 1      # Unchanged

readinessProbe:
  enabled: true
  timeoutSeconds: 5        # Was: 1s
  failureThreshold: 3      # Unchanged (faster detection)
  periodSeconds: 10        # Unchanged
  initialDelaySeconds: 10  # Unchanged (60s for Grafana)
  successThreshold: 1      # Unchanged
```

## Remaining Issues (To Be Addressed)

### High Priority - Longhorn (⚠️ CRITICAL - CASCADING FAILURE RISK)

**Problem**: Longhorn component restarts create **cascading failures**:
1. Longhorn pod fails health check and restarts
2. Volume attachments are delayed during restart
3. Application pods timeout waiting for volumes
4. Application pods restart, creating more volume operations
5. **Cascading effect** propagates across cluster

**Observed Restart Counts:**
| Component | Node | Restarts | Impact |
|-----------|------|----------|--------|
| engine-image-ei-f4f7aa25 | homelab-02 | **556** | CRITICAL - Causes volume unavailability |
| engine-image-ei-f4f7aa25 | homelab-04 | **82** | HIGH |
| longhorn-csi-plugin | homelab-03 | **37** | HIGH - Delays volume attachments |
| longhorn-csi-plugin | homelab-02 | **11** | MODERATE |

**Challenge**: Longhorn probe settings are **NOT configurable** via Helm:
- engine-image DaemonSets are dynamically created (not in chart)
- CSI plugin probes are hardcoded in Longhorn codebase
- No Helm values to modify probe settings

**Current Probe Config**:
```yaml
timeoutSeconds: 4        # Better than MetalLB/Prometheus
failureThreshold: 3
periodSeconds: 5         # But VERY frequent checks
# Grace period: 15 seconds (vs 25s for fixed components)
```

**Recommended Actions**:
1. ✅ **Monitor closely** - Watch for cascading failures (see longhorn/README.md)
2. ⏳ **Tune Longhorn settings** - Reduce concurrent operations to ease load
3. ⏳ **Optimize node resources** - Check for CPU/memory/IO bottlenecks
4. ⏳ **Consider manual patch** - Temporary fix (will be reset on upgrades)
5. ⏳ **File feature request** - Ask Longhorn to expose probe settings

**Documentation**: See `longhorn/README.md` section "Health Check Issues and Cascading Failures"

---

### Medium Priority - CSI Drivers (NFS/SMB)

1. **CSI Drivers** (NFS/SMB)
   - csi-nfs-node (homelab-03): 642 restarts
   - csi-smb-node (homelab-03): 698 restarts
   - csi-nfs-node (homelab-02): 102 restarts
   - csi-smb-node (homelab-02): 132 restarts
   - **Action needed**: Investigate deployment method and fix probes

### Medium Priority

Components with 1s timeout but currently stable (low/no restarts):

- CoreDNS (kube-system)
- metrics-server (kube-system)
- cert-manager-webhook (cert-manager)
- sealed-secrets-controller (kube-system)
- metallb-controller (metallb-system)
- capi-controller-manager (cattle-provisioning-capi-system)

**Action needed**: Monitor for issues; apply similar fixes proactively if restarts occur

## Verification Commands

### Check for New Restarts
```bash
# Watch all pods for restarts
kubectl get pods -A -o wide | grep -v "0/.*Running" | awk '{if ($4 > 5) print $0}'

# Check specific components
kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter
```

### Monitor for Liveness Probe Failures
```bash
# Watch for probe failures across all namespaces
kubectl get events -A --watch | grep -i "liveness"

# Check specific namespace
kubectl get events -n monitoring --sort-by='.lastTimestamp' | grep -i "liveness"
```

### Verify Probe Configuration
```bash
# MetalLB speaker
kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker \
  -o jsonpath='{.items[0].spec.containers[1].livenessProbe}' | jq .

# Prometheus node-exporter
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter \
  -o jsonpath='{.items[0].spec.containers[0].livenessProbe}' | jq .
```

## Node Resource Monitoring

homelab-03 showed the highest restart counts, suggesting potential resource contention:

```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage by node
kubectl top pods -A --sort-by=memory | grep homelab-03
kubectl top pods -A --sort-by=cpu | grep homelab-03

# Check node conditions
kubectl describe node homelab-03 | grep -A 10 "Conditions:"
```

## Expected Outcomes

After these fixes:
- ✅ MetalLB speaker pods should have 0 new restarts
- ✅ Prometheus node-exporter should have 0 new restarts
- ✅ Metrics collection should be continuous without gaps
- ✅ No "Liveness probe failed" events for fixed components
- ✅ Overall cluster stability should improve
- ⏳ Remaining CSI driver issues may still cause some instability

## References

- [HEALTH_CHECK_ANALYSIS.md](HEALTH_CHECK_ANALYSIS.md) - Detailed analysis
- [metallb/README.md](metallb/README.md) - MetalLB documentation
- [prometheus/README.md](prometheus/README.md) - Prometheus documentation
- [Kubernetes Probe Configuration](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## Changelog

| Date | Component | Action | Result |
|------|-----------|--------|--------|
| 2025-10-20 14:44 | MetalLB Speaker | Applied health check fixes | ✅ Stable, 0 restarts |
| 2025-10-20 14:56 | Prometheus Stack | Applied health check fixes | ✅ Stable, 0 restarts |
| 2025-10-20 15:10 | Longhorn | Documented cascading failure risk | ⚠️ Monitoring - probes not configurable |
