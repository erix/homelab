# High Availability Configuration for Critical Infrastructure

## Overview

This directory contains scripts and documentation for configuring high availability (HA) across critical Kubernetes infrastructure components in your homelab cluster.

## HA Strategy

### Design Philosophy

**2 Replicas + Hard Anti-Affinity** across 3 worker nodes

This strategy provides:
- ✅ **High Availability**: Survive 1 node failure
- ✅ **Resource Efficiency**: No over-provisioning (2 replicas vs 3)
- ✅ **Load Management**: Prevents overloading remaining nodes during failures
- ✅ **Automatic Failover**: Pods reschedule automatically on node failure

### Why 2 Replicas Instead of 3?

**With 3 replicas:**
- ❌ When 1 node fails: 2 replicas try to run on the same node (overload)
- ❌ With hard anti-affinity: System runs with only 2/3 replicas (reduced availability)
- ❌ Resource waste: 3 replicas for 3 nodes means limited scheduling flexibility

**With 2 replicas:**
- ✅ When all nodes healthy: 2 replicas on 2 different nodes
- ✅ When 1 node fails: Pod reschedules to the 3rd available node
- ✅ Always maintains 2/2 replicas (full availability)
- ✅ Better resource utilization: Leaves room for rebalancing

## Components Configured for HA

### Tier 1: Critical Infrastructure (Network & Storage)

| Component | Namespace | Replicas | Purpose | Impact if Down |
|-----------|-----------|----------|---------|----------------|
| **Longhorn CSI Controllers** | longhorn-system | 2 each | Storage operations | Storage provisioning/snapshots fail |
| - csi-provisioner | | | Volume creation | Can't create new volumes |
| - csi-attacher | | | Volume attachment | Can't attach volumes to pods |
| - csi-resizer | | | Volume expansion | Can't resize volumes |
| - csi-snapshotter | | | Snapshot management | Can't create snapshots |
| **CoreDNS** | kube-system | 2 | DNS resolution | Service discovery fails |
| **Traefik** | kube-system | 2 | Ingress controller | Web services unreachable |
| **MetalLB Controller** | metallb-system | 2 | LoadBalancer IPs | LoadBalancer services unavailable |

### Tier 2: Security & Certificate Management

| Component | Namespace | Replicas | Purpose | Impact if Down |
|-----------|-----------|----------|---------|----------------|
| **cert-manager** | cert-manager | 2 | Certificate controller | Cert renewals fail |
| **cert-manager-webhook** | cert-manager | 2 | Validation webhook | Can't validate cert resources |
| **cert-manager-cainjector** | cert-manager | 2 | CA injection | CA bundles not updated |
| **sealed-secrets-controller** | kube-system | 2 | Secret decryption | Can't deploy new secrets |

### Tier 3: Monitoring & Observability

| Component | Namespace | Replicas | Purpose | Impact if Down |
|-----------|-----------|----------|---------|----------------|
| **prometheus-operator** | monitoring | 2 | Prometheus management | Can't update Prometheus config |
| **kube-state-metrics** | monitoring | 2 | Cluster state metrics | Missing K8s object metrics |
| **grafana** | monitoring | 2 | Dashboard visualization | Can't access dashboards |
| **metrics-server** | kube-system | 2 | Resource metrics | kubectl top broken, HPA fails |

## Configuration Details

### Hard Anti-Affinity Rules

All components use `requiredDuringSchedulingIgnoredDuringExecution`:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app  # or app.kubernetes.io/name depending on component
          operator: In
          values:
          - <component-name>
      topologyKey: kubernetes.io/hostname
```

This ensures:
- No 2 replicas on the same node
- Pod stays Pending if it can't satisfy the rule
- Automatic distribution across nodes

### Deployment Strategy

All HA components use `Recreate` strategy:

```yaml
strategy:
  type: Recreate
```

Why? With `RollingUpdate` and hard anti-affinity:
- New pod tries to create before old one terminates
- Can't schedule (anti-affinity prevents 2 on same node)
- Update gets stuck

With `Recreate`:
- Terminates old pods first
- New pods can schedule anywhere
- Brief downtime during updates (acceptable for infrastructure)

## Usage

### Initial Setup

Apply HA configuration to all components:

```bash
cd /Users/eriksimko/github/homelab/k3s/apps/infrastructure
./apply-ha-configuration.sh
```

This will:
1. Apply hard anti-affinity to all components
2. Set Recreate deployment strategy
3. Scale all deployments to 2 replicas
4. Verify the configuration
5. Show pod distribution across nodes

**Estimated time**: 5-10 minutes

### Post-Upgrade Maintenance

After upgrading any of the following via Helm, re-run the HA script:

- Longhorn
- Traefik
- cert-manager
- Prometheus stack (kube-prometheus-stack)
- sealed-secrets
- metrics-server

```bash
# Example: After Longhorn upgrade
helm upgrade longhorn longhorn/longhorn -n longhorn-system
cd /Users/eriksimko/github/homelab/k3s/apps/infrastructure
./apply-ha-configuration.sh
```

### Selective Application

To apply HA to specific components only, edit the script and comment out unwanted phases.

For example, to only configure Longhorn:

```bash
# In apply-ha-configuration.sh, comment out Phase 2-7
# Keep only Phase 1: Longhorn CSI Controllers
```

## Behavior During Node Failures

### Scenario 1: Normal Operation (All Nodes Healthy)

```
Worker Nodes: [homelab-02] [homelab-03] [homelab-04]
CoreDNS:      [   Pod A   ] [   Pod B   ] [          ]
Traefik:      [          ] [   Pod A   ] [   Pod B   ]
MetalLB:      [   Pod A   ] [          ] [   Pod B   ]
```

Each component has 2 replicas distributed across different nodes.

### Scenario 2: One Node Fails (e.g., homelab-03)

```
Worker Nodes: [homelab-02] [homelab-03] [homelab-04]
                           [  FAILED  ]
CoreDNS:      [   Pod A   ] [   ----   ] [   Pod B*  ]  (* rescheduled from homelab-03)
Traefik:      [   Pod B*  ] [   ----   ] [   Pod B   ]  (* rescheduled from homelab-03)
MetalLB:      [   Pod A   ] [   ----   ] [   Pod B   ]  (no change, wasn't on homelab-03)
```

**What happens:**
1. Kubernetes detects homelab-03 is down
2. Pods on homelab-03 become unavailable
3. Scheduler reschedules them to homelab-02 or homelab-04
4. Hard anti-affinity ensures they don't co-locate with existing replicas
5. System maintains 2/2 replicas (full availability)

### Scenario 3: Node Recovers

```
Worker Nodes: [homelab-02] [homelab-03] [homelab-04]
                           [ RECOVERED ]
CoreDNS:      [   Pod A   ] [          ] [   Pod B   ]
Traefik:      [   Pod A   ] [          ] [   Pod B   ]
MetalLB:      [   Pod A   ] [          ] [   Pod B   ]
```

**What happens:**
1. homelab-03 comes back online
2. Pods remain on homelab-02 and homelab-04 (no automatic rebalancing)
3. System is stable with 2/2 replicas
4. (Optional) Manually rebalance by deleting a pod to force rescheduling to homelab-03

## Verification Commands

### Check Pod Distribution

```bash
# See all HA components and their node placement
kubectl get pods -A -o wide | grep -E "coredns|traefik|metallb-controller|cert-manager|prometheus|grafana|metrics-server|sealed-secrets|csi-"
```

### Check Replica Counts

```bash
# Verify all components have 2 replicas
kubectl get deploy -A | grep -E "coredns|traefik|metallb-controller|cert-manager|prometheus|grafana|metrics-server|sealed-secrets|csi-"
```

Expected output: `READY: 2/2` for all components

### Check Anti-Affinity Configuration

```bash
# Example: Check CoreDNS anti-affinity
kubectl get deploy coredns -n kube-system -o yaml | grep -A10 "podAntiAffinity"
```

Should show `requiredDuringSchedulingIgnoredDuringExecution`

### Check Deployment Strategy

```bash
# Example: Check Traefik strategy
kubectl get deploy traefik -n kube-system -o jsonpath='{.spec.strategy.type}'
```

Expected output: `Recreate`

### Pod Count Per Node

```bash
# See total pod distribution
for node in homelab-02 homelab-03 homelab-04; do
  count=$(kubectl get pods -A -o wide --field-selector spec.nodeName=$node --no-headers | wc -l | xargs)
  echo "$node: $count pods"
done
```

This helps verify that no single node is overloaded.

## Troubleshooting

### Issue: Pods Stuck in Pending After Script

**Symptoms:**
```bash
kubectl get pods -A | grep Pending
coredns-xxx   0/1   Pending
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look for: `didn't match pod anti-affinity rules`

**Resolution:**

This can happen if:
1. Only 2 worker nodes are available → Hard anti-affinity is working correctly
2. Deployment accidentally scaled to >2 replicas → Scale back to 2
3. Multiple pods from same deployment on same node → Delete extra pods

```bash
# Scale back to 2
kubectl scale deploy <deployment> -n <namespace> --replicas=2
```

### Issue: Uneven Distribution After Node Recovery

**Symptoms:**
homelab-02 has 35 pods, homelab-03 has 15 pods, homelab-04 has 20 pods

**Resolution:**

This is normal! With 2-replica strategy, pods don't automatically rebalance.

To manually rebalance:

```bash
# Example: Move CoreDNS pod from homelab-02 to homelab-03
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
# Identify pod on homelab-02
kubectl delete pod coredns-xxx -n kube-system
# Will reschedule to homelab-03 (due to anti-affinity with the other replica)
```

### Issue: Service Unavailable During Updates

**Symptoms:**
Brief service interruption when updating components

**Explanation:**
This is expected with `Recreate` strategy:
- Old pods terminate first
- New pods start
- Brief downtime (usually <10 seconds)

This is acceptable for infrastructure components and prevents the stuck update issues with RollingUpdate + hard anti-affinity.

### Issue: Configuration Lost After Helm Upgrade

**Symptoms:**
After `helm upgrade`, components revert to 1 replica and no anti-affinity

**Resolution:**
This is expected! Helm manages deployments and overwrites patches.

Always re-run after Helm upgrades:
```bash
cd /Users/eriksimko/github/homelab/k3s/apps/infrastructure
./apply-ha-configuration.sh
```

Consider creating a reminder/checklist for Helm upgrades.

## Monitoring Pod Distribution

### Alert When Pods Concentrate on One Node

You can use Prometheus to alert when a node has too many pods:

```yaml
# Example: Alert if homelab-03 exceeds 30 pods (already configured)
- alert: HomelabNodeHighPodCount
  expr: kubelet_running_pods{node="homelab-03"} > 25
  annotations:
    summary: "Node {{ $labels.node }} has {{ $value }} pods"
```

This alert helped identify the need for this HA configuration!

## Future Improvements

### Automate Post-Helm-Upgrade Configuration

Option 1: Create Helm post-upgrade hooks
Option 2: Use ArgoCD with custom health checks
Option 3: Create a cronjob that periodically checks and applies HA config

### Consider Horizontal Pod Autoscaler (HPA)

For components that benefit from scaling based on load:
- CoreDNS (scale based on DNS query rate)
- Traefik (scale based on request rate)

With hard anti-affinity, HPA would scale beyond 2 replicas only when needed.

### Node Affinity for Database Workloads

homelab-04 is labeled `node-role=database`. Consider adding node affinity to database workloads to keep them separated from infrastructure components.

## Component-Specific Notes

### Longhorn CSI Controllers

See `/Users/eriksimko/github/homelab/k3s/apps/longhorn/README.md` for detailed Longhorn-specific documentation.

### cert-manager

The webhook component is particularly sensitive to downtime. With 2 replicas, certificate validation continues even if one pod is updating.

### MetalLB

Only the **controller** needs HA (2 replicas). The **speaker** is a DaemonSet and already runs on all nodes.

### Prometheus Operator

StatefulSets (Prometheus, Alertmanager) remain at 1 replica. The **operator** deployment is what we scale to 2 for HA.

## References

- Kubernetes Pod Anti-Affinity: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity
- Deployment Strategies: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy
- High Availability Best Practices: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/

## Files in This Directory

- **README.md** (this file) - Comprehensive HA documentation
- **apply-ha-configuration.sh** - Main script to apply HA to all components
