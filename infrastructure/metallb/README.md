# MetalLB Configuration

MetalLB provides load balancer services for bare metal Kubernetes clusters.

## Deployment

MetalLB is deployed via Helm:

```bash
# Add the MetalLB Helm repository
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Install or upgrade MetalLB
helm upgrade --install metallb metallb/metallb \
  -n metallb-system \
  --create-namespace \
  -f values.yaml
```

## Health Check Optimization (Applied 2025-10-20)

### Problem
The MetalLB speaker pods were experiencing frequent restarts due to liveness probe timeouts. This was identified as the first sign of cluster instability.

**Symptoms:**
- Speaker pods restarting frequently (homelab-02: 21 restarts, homelab-03: 12, homelab-04: 8)
- Event logs showing: `Liveness probe failed: context deadline exceeded`
- Timeouts occurring under system load on Raspberry Pi ARM nodes

**Root Cause:**
The default liveness probe configuration had a 1-second timeout, which was too aggressive for ARM hardware. Under load, the probe endpoints couldn't respond within 1 second, causing Kubernetes to kill and restart containers.

### Solution
Updated `values.yaml` with optimized health check settings for ARM hardware:

**Changes:**
- `timeoutSeconds`: 1s → 5s (allows more time for responses under load)
- `failureThreshold`: 3 → 5 (more tolerance before restart)
- `periodSeconds`: 10s → 15s (reduces probe frequency and overhead)

**Result:**
- Before: 3 failures × 1 second timeout = 3 seconds total before restart
- After: 5 failures × 5 second timeout = 25 seconds total before restart

### Monitoring
To check for liveness probe failures:

```bash
# Check pod restart counts
kubectl get pods -n metallb-system -o wide

# View recent events for a specific speaker pod
kubectl get events -n metallb-system \
  --field-selector involvedObject.name=<pod-name> \
  --sort-by='.lastTimestamp'

# Check current probe configuration
kubectl get pods -n metallb-system <pod-name> \
  -o jsonpath='{.spec.containers[*].livenessProbe}' | jq .

# View logs
kubectl logs -n metallb-system <pod-name> --all-containers=true
```

### Expected Behavior
With the updated configuration, speaker pods should:
- Restart count should remain stable (no increases)
- No "Liveness probe failed" events
- Stable operation even during cluster load

## IP Address Pool Configuration

MetalLB IP pool: `192.168.11.200-250` (configured via IPAddressPool CRD)

To view current configuration:
```bash
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

## Troubleshooting

### Collecting Diagnostics
Use the MetalLB troubleshooting script:
```bash
/Users/eriksimko/github/homelab/k3s/metallb_logs.sh
```

This creates `metallb_report.tgz` with comprehensive logs and configuration.

### Common Issues

1. **Speaker pod restarts**: Check liveness probe configuration and events
2. **IPs not assigned**: Verify IPAddressPool and L2Advertisement CRDs
3. **Services stuck in pending**: Check speaker pod logs for errors
4. **Network connectivity**: Ensure speaker pods are running on all nodes

## References

- [MetalLB Official Documentation](https://metallb.universe.tf/)
- [MetalLB Helm Chart](https://github.com/metallb/metallb/tree/main/charts/metallb)
- Values file: `metallb/values.yaml`
- Diagnostic script: `/Users/eriksimko/github/homelab/k3s/metallb_logs.sh`
