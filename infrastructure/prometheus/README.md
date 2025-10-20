# Prometheus Stack Configuration

Kube-Prometheus-Stack provides comprehensive monitoring for the Kubernetes cluster.

## Deployment

Prometheus is deployed via Helm:

```bash
# Add the Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install or upgrade Prometheus stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f current-values.yaml \
  -f health-check-values.yaml
```

## Health Check Issues (Fixed 2025-10-20)

### Problem
The Prometheus node-exporter was experiencing **catastrophic restart counts** due to aggressive liveness probe timeouts:

**Restart Counts:**
- **homelab-03**: 7,444 restarts
- **homelab-02**: 455 restarts
- **homelab-04**: 160 restarts

**Root Cause:**
The default 1-second liveness probe timeout was insufficient for ARM hardware under load. When the system was busy, the node-exporter couldn't respond within 1 second, causing Kubernetes to kill and restart the container.

**Symptoms:**
- Extremely high restart counts on node-exporter pods
- Monitoring gaps and missing metrics
- Node-exporter contributing to overall cluster instability

### Solution Applied

Created `health-check-values.yaml` with optimized settings for all Prometheus components:

**Changes:**
- `timeoutSeconds`: 1s → 5s (allows more time for responses)
- `failureThreshold`: 3 → 5 (more tolerance before restart)
- `periodSeconds`: 10s → 15s (reduces probe overhead)
- `initialDelaySeconds`: Increased for Grafana (60s)

**Components Fixed:**
- ✅ prometheus-node-exporter (DaemonSet)
- ✅ prometheusOperator
- ✅ prometheus server
- ✅ alertmanager
- ✅ grafana
- ✅ kube-state-metrics

### Applying the Fix

```bash
# Apply health check optimizations
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f current-values.yaml \
  -f health-check-values.yaml

# Monitor pod rollout
kubectl rollout status daemonset/prometheus-prometheus-node-exporter -n monitoring

# Verify new configuration
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter \
  -o jsonpath='{.items[0].spec.containers[0].livenessProbe}' | jq .
```

## Monitoring

### Check Node Exporter Status

```bash
# Check all node-exporter pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o wide

# Check restart counts (should remain stable after fix)
kubectl get pods -n monitoring -o wide | grep node-exporter

# View logs from a specific node
kubectl logs -n monitoring prometheus-prometheus-node-exporter-<pod-suffix>

# Check for liveness probe failures
kubectl get events -n monitoring \
  --field-selector involvedObject.name=<pod-name> \
  --sort-by='.lastTimestamp'
```

### Access Monitoring Dashboards

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Port-forward to Alertmanager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
```

Then access:
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Alertmanager: http://localhost:9093

### Verify Metrics Collection

```bash
# Check if node-exporter metrics are being scraped
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
  -- wget -qO- 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="node-exporter")'
```

## Expected Behavior After Fix

- Node-exporter restart counts should stabilize (no new restarts)
- No "Liveness probe failed" events in monitoring namespace
- Continuous metrics collection without gaps
- Stable operation even during cluster load spikes

## Configuration Files

- `current-values.yaml` - Backup of existing Helm values
- `health-check-values.yaml` - Health check optimizations for ARM hardware
- `README.md` - This documentation

## Troubleshooting

### Node Exporter Not Starting

1. Check pod events:
   ```bash
   kubectl describe pod -n monitoring <pod-name>
   ```

2. Check logs:
   ```bash
   kubectl logs -n monitoring <pod-name>
   ```

3. Verify node resources:
   ```bash
   kubectl describe node <node-name>
   kubectl top node <node-name>
   ```

### High Restart Counts Continue

If restart counts continue to increase after applying the fix:

1. Check if the new configuration was applied:
   ```bash
   kubectl get pods -n monitoring <pod-name> \
     -o jsonpath='{.spec.containers[0].livenessProbe}' | jq .
   ```

2. Look for other issues in pod logs:
   ```bash
   kubectl logs -n monitoring <pod-name> --previous
   ```

3. Check node health:
   ```bash
   kubectl describe node <node-name>
   kubectl top pods -n monitoring
   ```

## References

- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Health Check Analysis](../HEALTH_CHECK_ANALYSIS.md)
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
