# Unifi Network Application & MongoDB Upgrade Plan

## Current State
- **Unifi Version:** 9.1.120-ls92
- **MongoDB Version:** 3.6
- **Namespace:** network
- **Storage:** longhorn-db-storage (optimized, single replica, strict-local)
- **Data:** 2 admins, 9 devices, 139 users, 2 sites

## Target State
- **Unifi Version:** 9.4.19-ls104 (latest)
- **MongoDB Version:** 7.0 (recommended for Unifi 9.x)

## Prerequisites
- ✅ All data backed up via Retain policy on PVs
- ✅ Unifi controller accessible and working
- ✅ MongoDB data verified and recovered

## Upgrade Strategy

### Phase 1: MongoDB Upgrade (3.6 → 7.0)
MongoDB requires incremental upgrades through major versions. Cannot skip versions.

**Upgrade Path:** 3.6 → 4.0 → 4.2 → 4.4 → 5.0 → 6.0 → 7.0

#### Step 1.1: Backup Current Data
```bash
# Create a backup job that copies MongoDB data
kubectl exec -n network mongodb-0 -- mongodump --out /data/backup-$(date +%Y%m%d)

# Or backup the entire PV by creating a snapshot
# (Longhorn supports snapshots natively)
```

#### Step 1.2: Upgrade MongoDB 3.6 → 4.0
```bash
# Update mongo-deployment.yaml
# Change: image: mongo:3.6
# To:     image: mongo:4.0

kubectl apply -f unifi/mongo/mongo-deployment.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=mongodb -n network --timeout=300s

# Verify version
kubectl exec -n network mongodb-0 -- mongo --version

# Run compatibility check
kubectl exec -n network mongodb-0 -- mongo admin --eval "db.adminCommand({setFeatureCompatibilityVersion: '4.0'})"
```

#### Step 1.3: Repeat for Each Version
Repeat the same process for:
- 4.0 → 4.2
- 4.2 → 4.4
- 4.4 → 5.0
- 5.0 → 6.0
- 6.0 → 7.0

**Important Notes:**
- Wait 5-10 minutes between upgrades to verify stability
- Check logs after each upgrade: `kubectl logs -n network mongodb-0 --tail=50`
- Verify data integrity: `kubectl exec -n network mongodb-0 -- mongo unifi --eval "db.admin.count()"`
- Each upgrade should return the same count (2 admins)

#### Step 1.4: Update Deployment File
After successful upgrade to 7.0, update the deployment file permanently:
```yaml
# unifi/mongo/mongo-deployment.yaml
containers:
- name: mongodb
  image: mongo:7.0  # Update this line
```

### Phase 2: Unifi Network Application Upgrade

#### Step 2.1: Pull Latest Image
Since using `:latest` tag, just restart the deployment:
```bash
# Delete pod to force pull latest image
kubectl delete pod -n network -l app=unifi

# Wait for new pod to start
kubectl wait --for=condition=ready pod -l app=unifi -n network --timeout=300s

# Check new version
kubectl exec -n network deployment/unifi -- cat /app/version.txt
```

#### Step 2.2: Verify Unifi Upgrade
1. Access https://unifi.erix-homelab.site
2. Verify all devices are visible
3. Check for any upgrade prompts or database migration messages
4. Verify network functionality

### Phase 3: Pin Versions (Recommended)

After successful upgrade, pin specific versions to prevent automatic updates:

```yaml
# unifi/mongo/mongo-deployment.yaml
containers:
- name: mongodb
  image: mongo:7.0.15  # Pin specific patch version

# unifi/unifi-deployment.yaml
containers:
- name: unifi
  image: linuxserver/unifi-network-application:9.4.19-ls104  # Pin specific version
```

**Benefits of Pinning:**
- Predictable upgrades
- Testing before production
- Avoid breaking changes
- Better disaster recovery

## Rollback Plan

### If MongoDB Upgrade Fails
```bash
# Rollback to previous version
kubectl patch statefulset mongodb -n network -p '{"spec":{"template":{"spec":{"containers":[{"name":"mongodb","image":"mongo:3.6"}]}}}}'

# Delete pod to force restart
kubectl delete pod mongodb-0 -n network

# Data is safe due to PV Retain policy
```

### If Unifi Upgrade Fails
```bash
# Rollback to specific version
kubectl set image deployment/unifi -n network unifi=linuxserver/unifi-network-application:9.1.120-ls92

# Or delete deployment and reapply old manifest
```

### If Data Corruption Occurs
```bash
# PV has Retain policy - data is never deleted
# Restore from Longhorn snapshot or backup

# If needed, recreate PVC pointing to backup PV
```

## Alternative: Conservative Approach

### Option A: Upgrade Only Unifi
- **Risk:** Low - MongoDB 3.6 still supported
- **Effort:** Minimal - just restart pod
- **Benefit:** Get latest Unifi features

### Option B: Upgrade MongoDB to 4.4 Only
- **Risk:** Medium - fewer upgrade steps
- **Effort:** Moderate - 3 version upgrades (3.6→4.0→4.2→4.4)
- **Benefit:** Better performance, still well-tested

### Option C: Full Upgrade (Recommended)
- **Risk:** Higher - more steps
- **Effort:** High - 7 version upgrades
- **Benefit:** Latest features, best security, future-proof

## Testing Checklist

After each upgrade, verify:
- [ ] MongoDB responds: `kubectl exec -n network mongodb-0 -- mongo --eval "db.version()"`
- [ ] Admin count correct: `kubectl exec -n network mongodb-0 -- mongo unifi --eval "db.admin.count()"` (should be 2)
- [ ] Device count correct: `kubectl exec -n network mongodb-0 -- mongo unifi --eval "db.device.count()"` (should be 9)
- [ ] Unifi UI accessible: https://unifi.erix-homelab.site
- [ ] All devices visible in dashboard
- [ ] Controller online at account.ui.com

## Timeline Estimate

- **Quick Upgrade (Unifi only):** 5 minutes
- **Conservative (MongoDB to 4.4 + Unifi):** 30-45 minutes
- **Full Upgrade (MongoDB to 7.0 + Unifi):** 1-2 hours

## Notes

- Current MongoDB 3.6 has been EOL since April 2021
- MongoDB 4.0 EOL: April 2022
- MongoDB 4.2 EOL: April 2023
- MongoDB 4.4 EOL: February 2024
- MongoDB 5.0: Supported until October 2024
- MongoDB 6.0: Supported until July 2025
- MongoDB 7.0: Supported until August 2026 (recommended target)

## References

- [Unifi Network Application Releases](https://github.com/linuxserver/docker-unifi-network-application/releases)
- [MongoDB Upgrade Documentation](https://www.mongodb.com/docs/manual/release-notes/)
- [LinuxServer.io Documentation](https://docs.linuxserver.io/images/docker-unifi-network-application/)
