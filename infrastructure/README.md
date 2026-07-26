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
cd infrastructure
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
cd infrastructure
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
cd infrastructure
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
Option 2: Represent the settings in Flux-managed manifests with health checks
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

See [longhorn/README.md](longhorn/README.md) for detailed
Longhorn-specific documentation.

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

## Tailscale Kubernetes Operator - Secure Remote Access

### Overview

The Tailscale Kubernetes Operator provides secure, zero-trust network access to your cluster services from anywhere, without exposing them to the public internet. Services are accessible through your private Tailscale network (Tailnet) with end-to-end encryption.

**Repository state**: Operator configuration and a sealed OAuth secret are
present. Verify live status with `kubectl get pods -n tailscale`.

### What is Tailscale?

Tailscale creates a secure mesh VPN using WireGuard. The Kubernetes operator allows you to expose cluster services directly to your Tailnet by simply adding an annotation.

### Installation

See `infrastructure/tailscale/` for the operator's configuration files.

**Components represented in the configuration:**
- Tailscale Operator (manages service exposure)
- OAuth authentication (sealed secret)
- Custom Resource Definitions (CRDs) for advanced features
- RBAC permissions

**Requirements:**

- A Tailscale OAuth client with the scopes required by the chart
- ACL ownership for the operator and workload tags
- The committed Sealed Secret for OAuth credentials

### Exposing Services

To make any service accessible through Tailscale, simply add an annotation:

#### Method 1: Command Line

```bash
kubectl annotate service <service-name> -n <namespace> tailscale.com/expose=true
```

**Example:**
```bash
kubectl annotate service home-assistant -n home-assistant tailscale.com/expose=true
```

#### Method 2: YAML Manifest

Add the annotation to your service definition:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: default
  annotations:
    tailscale.com/expose: "true"
spec:
  type: ClusterIP  # Works with ClusterIP, LoadBalancer, or NodePort
  selector:
    app: my-app
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

#### Optional: Custom Hostname

Set a custom hostname instead of the default `<namespace>-<service>` format:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "my-custom-name"
```

This creates `my-custom-name.<tailnet>.ts.net` instead of `default-my-service.<tailnet>.ts.net`.

### What Happens When You Expose a Service

1. **Operator Detects**: The Tailscale operator watches for services with the `tailscale.com/expose` annotation
2. **Proxy Created**: Automatically creates a Tailscale proxy pod (`ts-<namespace>-<service>-xxxxx-0`) in the `tailscale` namespace
3. **Tailnet Registration**: Registers the proxy on your Tailnet with tags `tag:k8s`
4. **DNS Assignment**: Assigns a hostname: `<namespace>-<service>.<tailnet>.ts.net`
5. **Ready**: Service is immediately accessible from any device on your Tailscale network

### Currently Exposed Services

| Service | Namespace | Tailscale Hostname | Tailscale IP | Ports | Purpose |
|---------|-----------|-------------------|--------------|-------|---------|
| ib-gateway | default | `default-ib-gateway.tail9139a.ts.net` | `100.77.222.105` | 4001, 4002, 5900 | Interactive Brokers Gateway |

### Verifying Service Exposure

#### Check Tailscale Proxy Pod

```bash
# List all Tailscale proxies
kubectl get pods -n tailscale

# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# operator-xxx               1/1     Running   0          1h
# ts-default-myservice-0     1/1     Running   0          5m
```

#### Get Tailscale Hostname

```bash
# From inside the proxy pod
kubectl exec -n tailscale ts-<service>-xxxxx-0 -c tailscale -- tailscale status

# Look for your service in the output:
# 100.x.x.x  <namespace>-<service>    <namespace>-<service>.<tailnet>.ts.net  linux  -
```

#### Test Access

From any device on your Tailscale network:

```bash
# Using hostname
curl http://<namespace>-<service>.<tailnet>.ts.net:<port>

# Using Tailscale IP
curl http://100.x.x.x:<port>
```

### Removing Tailscale Exposure

Simply remove the annotation:

```bash
kubectl annotate service <service-name> -n <namespace> tailscale.com/expose-
```

The operator will automatically:
- Remove the Tailscale proxy pod
- Unregister the device from your Tailnet
- Clean up associated resources

### Operator Management

#### Check Operator Status

```bash
kubectl get pods -n tailscale -l app=operator
```

#### View Operator Logs

```bash
kubectl logs -n tailscale -l app=operator -f
```

#### Restart Operator

```bash
kubectl rollout restart deployment/operator -n tailscale
```

### Security Considerations

**✅ Advantages:**
- Zero-trust network access (device authentication required)
- End-to-end encryption (WireGuard)
- No public internet exposure
- No port forwarding or firewall rules needed
- MagicDNS for easy hostname resolution
- Audit logs in Tailscale admin console

**⚠️ Best Practices:**
- Only expose services that need remote access
- Use Tailscale ACLs to restrict access to specific users/devices
- Regularly review exposed services: `kubectl get svc -A -o json | jq '.items[] | select(.metadata.annotations."tailscale.com/expose" == "true") | {namespace:.metadata.namespace, name:.metadata.name}'`
- Monitor Tailscale admin console for unexpected devices

### Tailscale ACL Configuration

Your current ACL includes these tags for Kubernetes services:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s": ["autogroup:admin"]
  }
}
```

**Tags explained:**
- `tag:k8s-operator`: Used by the Tailscale operator pod itself
- `tag:k8s`: Applied to all service proxy pods
- `autogroup:admin`: Allows any admin to create devices with these tags

### Troubleshooting

#### Proxy Pod Not Created

**Check:**
1. Annotation is correct: `kubectl get svc <service> -n <namespace> -o yaml | grep tailscale`
2. Operator is running: `kubectl get pods -n tailscale -l app=operator`
3. Operator logs: `kubectl logs -n tailscale -l app=operator --tail=50`

#### Proxy Pod CrashLoopBackOff

**Common causes:**
1. **OAuth credentials expired/invalid**: Check sealed secret was unsealed properly
   ```bash
   kubectl get secret operator-oauth -n tailscale
   ```
2. **ACL tags not configured**: Verify tags exist in Tailscale admin console
3. **OAuth scopes missing**: Ensure client has `devices:write` and `auth_keys:write`

#### Can't Access Service from Tailscale

**Check:**
1. Device is connected to Tailscale: `tailscale status`
2. MagicDNS is enabled: `tailscale status | grep MagicDNS`
3. Service proxy is running: `kubectl get pods -n tailscale | grep ts-<service>`
4. Correct port is being used
5. Service itself is healthy: `kubectl get pods -n <namespace>`

### Maintenance

#### After Operator Updates

If you reinstall or update the Tailscale operator:

```bash
cd infrastructure/tailscale

# Reapply sealed OAuth secret
kubectl apply -f operator-oauth-sealed.yaml

# Restart operator
kubectl rollout restart deployment/operator -n tailscale
```

#### Updating OAuth Credentials

1. Generate new OAuth client in Tailscale admin console
2. Update the local, unsealed `infrastructure/tailscale/operator-secret.yaml`
   with new credentials
3. Seal the secret:
   ```bash
   cd infrastructure/tailscale
   kubeseal -f operator-secret.yaml -w operator-oauth-sealed.yaml
   ```
4. Apply and restart:
   ```bash
   kubectl apply -f operator-oauth-sealed.yaml
   kubectl rollout restart deployment/operator -n tailscale
   ```

### Advanced Features

The operator supports additional features via CRDs:

- **Connector**: Deploy Tailscale subnet routers or exit nodes
- **ProxyClass**: Define reusable proxy configurations
- **DNSConfig**: Customize DNS settings
- **Recorder**: Configure traffic recording

See official Tailscale documentation for details: https://tailscale.com/kb/1236/kubernetes-operator

### Files in Tailscale Directory

- `infrastructure/tailscale/`
  - `README.md` - Detailed setup guide
  - `install.sh` - Helm installation and upgrade workflow
  - `values.yaml` - Helm values
  - `operator-oauth-sealed.yaml` - Committed Sealed Secret
  - `ib-gateway-service-patch.yaml` - Example service annotation patch

An ignored `operator-secret.yaml` may be created temporarily when rotating the
OAuth credentials. Never commit it.

### References

- Tailscale Kubernetes Operator: https://tailscale.com/kb/1236/kubernetes-operator
- Tailscale ACLs: https://tailscale.com/kb/1018/acls
- OAuth Clients: https://tailscale.com/kb/1215/oauth-clients

---

## Files in This Directory

- **README.md** (this file) - Comprehensive HA documentation
- **apply-ha-configuration.sh** - Main script to apply HA to all components
- **tailscale/** - Tailscale Kubernetes Operator configuration
