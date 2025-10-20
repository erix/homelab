# Cascading Failure Analysis - Spontaneous CPU Spikes

**Date**: 2025-10-20
**Issue**: Recurring pattern of spontaneous CPU spikes leading to complete cluster collapse

## Problem Description

System runs smoothly, then suddenly:
1. **CPU spike** occurs on one or more nodes
2. **Cascading failure** begins
3. **Entire cluster becomes unstable**
4. **Recovery takes significant time** (10-30+ minutes)

This pattern repeats multiple times, making the cluster unreliable.

## Identified Spike Triggers

### 1. **Longhorn Snapshots and Backups** ⚠️ HIGH PROBABILITY

**Observed Schedule:**
```
Daily at midnight:   database-snapshot (0 0 * * ?)
Daily at 1:00 AM:    app-snapshot (0 1 * * ?)
Weekly Monday 2 AM:  database-backup (0 2 ? * MON)
Weekly Monday 2 AM:  app-backup (0 2 ? * MON)
```

**Why This Causes Spikes:**
- **Snapshot operations** require reading entire volumes
- **Multiple volumes** processed simultaneously (concurrency=1, but multiple jobs overlap)
- **I/O intensive** on SD card/slow storage
- **CPU spikes** from checksum calculations, compression
- **Memory pressure** from buffering snapshot data

**Impact:**
- Midnight snapshot starts
- 1 AM snapshot starts (first one may still be running)
- Combined I/O load triggers health check timeouts
- Longhorn probes start failing
- **Cascading effect begins**

**Evidence:**
```
database-snapshot   0 0 * * ?   # Midnight
app-snapshot        0 1 * * ?   # 1 AM (may overlap with midnight job)
```

With 3-way replication and ~18 volumes, this creates **significant I/O burst**.

### 2. **Prometheus Scraping and Compaction** ⚠️ MODERATE PROBABILITY

**Scrape Interval**: 30 seconds (from alert rules)

**Why This Causes Spikes:**
- **Node exporter** scrapes metrics from all pods
- **Metrics cardinality** increases with pod count
- **Memory spikes** during scrape aggregation
- **Periodic compaction** of time-series database
- **Alert evaluation** runs every 30s

**Compounding Factors:**
- 26+ pods on homelab-02
- Each pod has multiple containers
- Longhorn volumes add significant metrics
- No resource limits on Prometheus components

**Evidence from current crisis:**
- Prometheus pods all scheduled to homelab-02
- Node became NotReady shortly after Prometheus upgrade
- High CPU on prometheus-node-exporter during crisis

### 3. **Longhorn Volume Replica Rebuilds** ⚠️ MODERATE PROBABILITY

**Trigger Scenarios:**
- Node restart or network interruption
- Volume becomes degraded
- Automatic replica replenishment

**Why This Causes Spikes:**
- **Full volume copy** across network
- **CPU intensive** checksum verification
- **I/O intensive** on both source and destination
- **Multiple replicas** may rebuild simultaneously

**Settings:**
```yaml
concurrentReplicaRebuildPerNodeLimit: 5  # Default
replicaReplenishmentWaitInterval: 600    # 10 minutes
```

**Impact:**
- After node recovers from NotReady
- Longhorn starts rebuilding degraded replicas
- 5 concurrent rebuilds × 3 replicas = massive load
- Triggers another cascade

### 4. **iptables Operations** ⚠️ SEVERE DURING CRISIS

**Observed During Crisis:**
```
iptables ChainExists took 91 seconds (should be <1s)
```

**Why This Happens:**
- **iptables lock** contention under load
- **kube-proxy** updates rules frequently
- **MetalLB speaker** manages rules for LoadBalancer services
- **Linear rule scanning** in iptables (not optimized for many rules)

**Cascade Effect:**
- Health probes use network
- Network requires iptables
- iptables blocked → probes timeout
- More restarts → more iptables updates
- **Death spiral**

### 5. **Volume Metrics Calculation** ⚠️ SEVERE DURING CRISIS

**Observed During Crisis:**
```
Calculate volume metrics took 10-43 seconds per volume
26 pods × multiple volumes = significant delay
```

**Why This Happens:**
- **kubelet** calculates volume usage for reporting
- **du -s** equivalent operation on each mount
- **Slow storage** (SD card) makes this very expensive
- **NFS/SMB** volumes compound the delay (network RTT)

**Cascade Effect:**
- High load slows disk I/O
- Volume metrics take longer
- kubelet blocked waiting for metrics
- Can't send heartbeats to API server
- Node marked NotReady

### 6. **Memory Pressure (No Swap)** ⚠️ MODERATE PROBABILITY

**Current Configuration:**
```
Memory: 3.8Gi total
Swap:   0B (NONE configured)
```

**Why This Causes Spikes:**
- **No overflow** when memory pressure occurs
- **OOM killer** starts terminating processes
- **Aggressive reclaim** causes CPU spikes
- **Page cache thrashing** under pressure

**Common Triggers:**
- Prometheus scrape spike
- Longhorn snapshot buffering
- Multiple pods starting simultaneously
- Java applications (heap allocation)

### 7. **Pod Scheduling Bursts** ⚠️ MODERATE PROBABILITY

**Scenarios:**
- Helm upgrades (like Prometheus today)
- DaemonSet updates
- Node recovery (rescheduling)
- Deployments with multiple replicas

**Why This Causes Spikes:**
- **Multiple pods** start simultaneously
- **Image pulls** compete for bandwidth
- **Init containers** run in sequence
- **Liveness probes** start immediately
- **Volume attachments** all requested at once

**Evidence from Today:**
- Prometheus upgrade triggered multiple pod restarts
- Grafana, Alertmanager, Prometheus all starting together
- homelab-02 became NotReady shortly after

## The Cascading Failure Chain

```
[Trigger Event]
    ↓
CPU/Memory/IO Spike
    ↓
Health Probes Start Timing Out
    ↓
Pods Restart
    ↓
More Volume Operations (attach/detach)
    ↓
iptables Lock Contention Increases
    ↓
Network Operations Slow Down
    ↓
More Probes Timeout
    ↓
More Pods Restart
    ↓
Volume Metrics Calculations Take Minutes
    ↓
Kubelet Can't Send Heartbeats
    ↓
Node Marked NotReady
    ↓
Pods Evicted/Rescheduled
    ↓
Even More Volume Operations
    ↓
[COMPLETE COLLAPSE]
    ↓
Slow Recovery (10-30+ minutes)
```

## Why Recovery Takes So Long

1. **iptables cleanup** - Removing old rules under load
2. **Volume reattachment** - Longhorn must reattach all volumes
3. **Replica rebuilds** - Volumes became degraded, need rebuilding
4. **Pod rescheduling** - Kubernetes moving pods around
5. **Resource contention** - Everything competing for limited resources
6. **Cascade continues** - New probes fail during recovery
7. **Eventually stabilizes** - Once load drops enough

## Evidence from Current Crisis (2025-10-20 15:10)

**Timeline:**
```
14:56 - Prometheus Helm upgrade completed
15:06 - Last successful heartbeat from homelab-02
15:10 - homelab-02 marked NotReady
15:14 - Load average: 60.09 (on 4-CPU system!)
```

**Logs from homelab-02 at 15:10:**
```
Longhorn engine-image probe timeout (4s exceeded)
CSI driver probe timeout (15s exceeded)
iptables ChainExists: 91 seconds
Volume metrics calculation: 10-43 seconds per volume
"Unable to authenticate the request: context canceled"
```

**System Resources at 15:14:**
```
Load average: 60.09, 42.49, 22.38
Memory: 3.4Gi / 3.8Gi (89% used, only 26Mi free)
Swap: 0B (none)
```

## Likely Triggers for Your Recurring Spikes

Based on the analysis, the **most likely recurring triggers** are:

### #1 Midnight/Early Morning Spikes → **Longhorn Snapshots**
- Daily at midnight: database snapshot
- Daily at 1 AM: app snapshot
- I/O intensive operations on slow storage
- Multiple volumes × 3 replicas = massive load

### #2 Any Time Spikes → **Prometheus Scraping Bursts**
- Every 30 seconds normal scrape
- Periodic compaction (unpredictable timing)
- High pod count increases metrics cardinality
- No resource limits allow unbounded growth

### #3 Recovery-Triggered Spikes → **Replica Rebuilds**
- After any node issue
- Longhorn rebuilds degraded replicas
- Up to 5 concurrent rebuilds
- Creates another spike → another cascade

## Recommended Fixes

### Immediate (Stop the Bleeding)

1. **Reduce Longhorn Snapshot Concurrency**
   ```yaml
   # longhorn/values.yaml
   defaultSettings:
     concurrentReplicaRebuildPerNodeLimit: 2  # Down from 5
     concurrentVolumeBackupRestorePerNodeLimit: 2  # Down from 5
   ```

2. **Stagger Snapshot Times**
   ```yaml
   database-snapshot: 0 0 * * ?    # Keep midnight
   app-snapshot:      0 3 * * ?    # Move to 3 AM (not 1 AM)
   database-backup:   0 2 ? * MON  # Keep Monday 2 AM
   app-backup:        0 2 ? * WED  # Move to Wednesday
   ```

3. **Add Prometheus Resource Limits**
   ```yaml
   # prometheus/health-check-values.yaml (already created)
   # Add this:
   prometheus:
     prometheusSpec:
       resources:
         requests:
           cpu: 500m
           memory: 2Gi
         limits:
           cpu: 2
           memory: 4Gi
   ```

4. **Enable Swap** (Emergency Relief)
   ```bash
   # On each node
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

### Short-Term (Reduce Likelihood)

5. **Add Pod Anti-Affinity for Prometheus**
   Spread Prometheus components across nodes

6. **Increase Probe Timeouts** (where possible)
   - Already done for MetalLB (25s grace period)
   - Already done for Prometheus (25s grace period)
   - Longhorn: not easily configurable

7. **Monitor and Alert on Load**
   ```yaml
   - alert: HighNodeLoad
     expr: node_load1 > 8  # 2× CPU count
     for: 2m
   ```

### Long-Term (Prevent Cascades)

8. **Faster Storage**
   - Replace SD cards with SSDs
   - Use USB 3.0 SSDs for boot/storage
   - Significantly reduces I/O bottleneck

9. **More Memory**
   - 8GB RAM minimum per node
   - Reduces memory pressure
   - Allows better caching

10. **Redesign Longhorn Strategy**
    - Reduce replica count from 3 to 2
    - Use remote backup instead of local snapshots
    - Schedule backups during known low-usage times

11. **Pod Resource Quotas**
    - Enforce limits on all pods
    - Prevent resource exhaustion
    - QoS guarantees for critical workloads

## Monitoring for Spikes

```bash
# Watch for load spikes
watch -n 5 'kubectl top nodes'

# Monitor Longhorn operations
kubectl get recurringjobs -n longhorn-system
kubectl get volumes -n longhorn-system | grep -v Healthy

# Check for running snapshots/backups
kubectl get pods -n longhorn-system | grep -E "snapshot|backup"

# Watch for node NotReady
kubectl get nodes -w
```

## Quick Recovery Procedure

When a spike occurs and nodes become NotReady:

1. **Don't panic** - Let it settle for 5-10 minutes
2. **Monitor load** - `kubectl top nodes`
3. **Check Longhorn** - Look for snapshot/backup jobs
4. **If stuck** - Consider restarting k3s-agent on affected node
5. **After recovery** - Check which volumes need rebuilding
6. **Prevent recurrence** - Identify and address the trigger

## Files Created

- `CASCADING_FAILURE_ANALYSIS.md` - This document
- `HEALTH_CHECK_ANALYSIS.md` - Component-level health check analysis
- `FIXES_APPLIED.md` - Fixes that have been applied
- `longhorn/README.md` - Longhorn cascading failure documentation
- `metallb/README.md` - MetalLB health check fixes
- `prometheus/README.md` - Prometheus health check fixes

## Next Steps

1. Apply immediate fixes (snapshot staggering, resource limits)
2. Monitor for next 24-48 hours
3. Document when spikes occur to confirm pattern
4. Consider hardware upgrades (SSD, more RAM)
5. Long-term: Reduce cluster complexity or increase node resources
