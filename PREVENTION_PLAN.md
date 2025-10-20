# Cascading Failure Prevention Plan

**Date**: 2025-10-20
**Purpose**: Prevent the recurring spike-and-collapse pattern in the homelab cluster

## Summary of Today's Findings

We identified **7 triggers** for cascading failures and witnessed a **complete death spiral** caused by zombie pods during a Prometheus restart. The cluster went from stable → NotReady → Load 51 → complete collapse → 30-minute recovery.

## Prevention Strategy (Priority Order)

### 🔴 CRITICAL - Apply Immediately

#### 1. Stagger Longhorn Snapshots (Highest ROI)

**Problem**: Snapshots overlap at midnight-1 AM, causing massive I/O spike on slow storage

**Solution**:
```bash
# Edit Longhorn recurring jobs
kubectl edit recurringjob database-snapshot -n longhorn-system
# Change: 0 0 * * ? (midnight) → Keep as is

kubectl edit recurringjob app-snapshot -n longhorn-system
# Change: 0 1 * * ? (1 AM) → 0 3 * * ? (3 AM)

kubectl edit recurringjob app-backup -n longhorn-system
# Change: 0 2 ? * MON (Monday 2 AM) → 0 2 ? * WED (Wednesday 2 AM)
```

**Expected Impact**: Eliminates midnight spike pattern, spreads load across multiple nights

**Verification**:
```bash
kubectl get recurringjobs -n longhorn-system
```

---

#### 2. Reduce Longhorn Concurrent Operations

**Problem**: Up to 5 concurrent replica rebuilds can overwhelm ARM nodes

**Solution**:
```bash
# Create or update longhorn/values.yaml
cat > longhorn/values.yaml <<EOF
defaultSettings:
  defaultDataPath: /storage01

  # Reduce concurrent operations
  concurrentReplicaRebuildPerNodeLimit: 2  # Down from 5
  concurrentVolumeBackupRestorePerNodeLimit: 2  # Down from 5

  # Increase wait time before rebuilding
  replicaReplenishmentWaitInterval: 600  # 10 minutes

  # Allow volumes to be created even if degraded
  allowVolumeCreationWithDegradedAvailability: true
EOF

# Apply changes
helm upgrade longhorn longhorn/longhorn -n longhorn-system -f longhorn/values.yaml
```

**Expected Impact**: Reduces load during replica rebuilds, prevents rebuild cascades

---

#### 3. Add Prometheus Resource Limits

**Problem**: Prometheus can consume unbounded memory/CPU during scrapes

**Solution**:
```bash
# Update prometheus/health-check-values.yaml
cat >> prometheus/health-check-values.yaml <<EOF

# Resource limits to prevent unbounded growth
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2
        memory: 4Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

grafana:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi
EOF

# Apply changes
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus/current-values.yaml \
  -f prometheus/health-check-values.yaml
```

**Expected Impact**: Prevents Prometheus from consuming all node resources

---

#### 4. Add Pod Anti-Affinity for Prometheus

**Problem**: All Prometheus pods can schedule to the same node, creating concentration risk

**Solution**:
```bash
# Add to prometheus/health-check-values.yaml
cat >> prometheus/health-check-values.yaml <<EOF

# Spread Prometheus components across nodes
prometheus:
  prometheusSpec:
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/name
                    operator: In
                    values:
                      - prometheus
              topologyKey: kubernetes.io/hostname

alertmanager:
  alertmanagerSpec:
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/name
                    operator: In
                    values:
                      - alertmanager
              topologyKey: kubernetes.io/hostname

grafana:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                    - grafana
            topologyKey: kubernetes.io/hostname
EOF

# Apply
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus/current-values.yaml \
  -f prometheus/health-check-values.yaml
```

**Expected Impact**: Distributes Prometheus load across all nodes

---

### 🟡 HIGH PRIORITY - Apply This Week

#### 5. Enable Swap (Emergency Relief Valve)

**Problem**: No swap means OOM killer activates under memory pressure, causing aggressive process termination

**Solution**:
```bash
# On each node (homelab-02, homelab-03, homelab-04)
for node in homelab-02 homelab-03 homelab-04; do
  ssh $node 'sudo bash -c "
    # Create 2GB swap file
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo \"/swapfile none swap sw 0 0\" >> /etc/fstab

    # Verify
    swapon --show
    free -h
  "'
done
```

**Expected Impact**: Prevents OOM during memory pressure, gives cluster breathing room

**Trade-off**: Swap on SD cards reduces lifespan, but prevents complete failures

---

#### 6. Set Up Node Load Alerts

**Problem**: No early warning when nodes start becoming overloaded

**Solution**:
```bash
# Add to Prometheus alerts (via Grafana or AlertManager config)
# These thresholds are for 4-CPU ARM nodes
cat > monitoring/node-load-alerts.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: homelab-node-load
  namespace: monitoring
spec:
  groups:
    - name: node-load
      interval: 30s
      rules:
        - alert: NodeLoadHigh
          expr: node_load1 > 8  # 2× CPU count
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Node {{ \$labels.node }} load is high"
            description: "Load average is {{ \$value }} (threshold: 8)"

        - alert: NodeLoadCritical
          expr: node_load1 > 16  # 4× CPU count
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ \$labels.node }} load is CRITICAL"
            description: "Load average is {{ \$value }} - cascading failure likely"

        - alert: NodeMemoryPressure
          expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Node {{ \$labels.node }} has low memory"
            description: "Only {{ \$value | humanizePercentage }} memory available"
EOF

kubectl apply -f monitoring/node-load-alerts.yaml
```

**Expected Impact**: Early warning before cascading failures begin

---

#### 7. Create Force-Delete Recovery Script

**Problem**: Manual force-delete during crisis is error-prone and slow

**Solution**:
```bash
cat > /Users/eriksimko/github/homelab/k3s/force-delete-terminating.sh <<'EOF'
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
EOF

chmod +x /Users/eriksimko/github/homelab/k3s/force-delete-terminating.sh
```

**Usage during crisis**:
```bash
cd /Users/eriksimko/github/homelab/k3s
./force-delete-terminating.sh homelab-02
```

---

### 🟢 MEDIUM PRIORITY - Apply This Month

#### 8. Reduce Prometheus Scrape Cardinality

**Problem**: High pod count creates high metrics cardinality, increasing memory usage

**Solution**:
```yaml
# Add to prometheus/health-check-values.yaml
prometheus:
  prometheusSpec:
    # Reduce retention (currently 10 days)
    retention: 7d

    # Enable WAL compression (already enabled)
    walCompression: true

    # Limit scraped metrics
    additionalScrapeConfigs:
      - job_name: 'kubernetes-pods'
        metric_relabel_configs:
          # Drop high-cardinality metrics you don't need
          - source_labels: [__name__]
            regex: 'go_.*|process_.*'
            action: drop
```

**Expected Impact**: Reduces Prometheus memory footprint

---

#### 9. Consider Reducing Longhorn Replicas

**Problem**: 3-way replication is expensive on limited hardware

**Solution** (Only if acceptable for your use case):
```yaml
# For non-critical volumes, use 2 replicas instead of 3
# Edit individual volumes or change default

# Via Longhorn UI or:
kubectl patch volume <volume-name> -n longhorn-system \
  --type='json' -p='[{"op": "replace", "path": "/spec/numberOfReplicas", "value": 2}]'
```

**Trade-off**: Lower redundancy but less load

**Do NOT reduce replicas for**: Databases, critical application data

---

### 🔵 LONG-TERM - Hardware Upgrades

#### 10. Replace SD Cards with SSDs

**Problem**: SD card I/O is the bottleneck for Longhorn operations

**Solution**:
- USB 3.0 SSD boot drives
- Or: Keep SD for boot, use SSD for /storage01

**Expected Impact**: 10-100× faster I/O, eliminates snapshot spikes

---

#### 11. Increase RAM to 8GB per Node

**Problem**: 4GB RAM is tight for multiple workloads

**Solution**: Upgrade Raspberry Pi to 8GB models

**Expected Impact**: Eliminates memory pressure, allows better caching

---

## Quick Reference: Crisis Response

### If Node Goes NotReady

1. **Don't panic** - Let it settle for 5-10 minutes
2. **Check load**: `kubectl top nodes` or `ssh <node> "cat /proc/loadavg"`
3. **Look for triggers**:
   - Longhorn snapshots running?
   - Recent Helm upgrades?
   - Replica rebuilds?
4. **If zombie pods exist**: Run force-delete script
5. **If still stuck after 15 min**: Restart k3s-agent

### Monitoring Commands

```bash
# Watch node status
watch -n 5 'kubectl get nodes'

# Check for terminating pods
kubectl get pods -A | grep Terminating

# View load on specific node
ssh homelab-02 "uptime; free -h"

# Check Longhorn operations
kubectl get recurringjobs -n longhorn-system
kubectl get volumes -n longhorn-system | grep -v Healthy

# Find pods with high restart counts
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort -k2 -nr | head -20
```

---

## Implementation Checklist

**Week 1 (Critical):**
- [ ] Stagger Longhorn snapshot schedules
- [ ] Reduce Longhorn concurrent operations
- [ ] Add Prometheus resource limits
- [ ] Add Prometheus pod anti-affinity
- [ ] Test force-delete recovery script

**Week 2 (High Priority):**
- [ ] Enable swap on all nodes
- [ ] Set up node load alerts
- [ ] Document recovery procedures

**Month 1 (Medium Priority):**
- [ ] Reduce Prometheus retention/cardinality
- [ ] Review and optimize non-critical volume replicas
- [ ] Monitor for recurring patterns

**Long-term:**
- [ ] Budget for SSD upgrades
- [ ] Consider RAM upgrades
- [ ] Evaluate cluster sizing vs. workload

---

## Success Metrics

After implementing these fixes, you should see:

✅ **No more midnight spikes** - Staggered snapshots
✅ **Lower baseline load** - Resource limits in place
✅ **Faster recovery** - Pod anti-affinity + force-delete script
✅ **Fewer restarts** - Health check timeouts already fixed
✅ **Early warnings** - Load alerts catch issues early

**Target**: Zero NotReady events over 7 days after implementation

---

## Files to Maintain

- `PREVENTION_PLAN.md` (this file) - Prevention strategies
- `CASCADING_FAILURE_ANALYSIS.md` - Root cause analysis
- `force-delete-terminating.sh` - Emergency recovery script
- `longhorn/values.yaml` - Longhorn configuration
- `prometheus/health-check-values.yaml` - Prometheus configuration
- `monitoring/node-load-alerts.yaml` - Alert rules

---

## Final Notes

The cluster is fundamentally **resource-constrained**. These fixes buy you stability, but the long-term solution is either:

1. **Reduce workload** - Consolidate applications, remove non-essential services
2. **Upgrade hardware** - SSD + 8GB RAM makes everything better
3. **Accept occasional instability** - With these fixes, recovery is faster

Choose based on your budget and tolerance for downtime.

**The good news**: With health check fixes + prevention measures, you should see 90% reduction in cascading failures! 🎯
