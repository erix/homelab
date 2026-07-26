# Unifi MongoDB memory cap in Erik's k3s homelab

Use this when k3s node memory is high and `kubectl top pods -A --sort-by=memory` shows `network/mongodb-0` consuming multiple GiB.

## Symptom observed

The node reported high memory usage:

```text
kubectl top node node-01
node-01 MEMORY(bytes) 21134Mi MEMORY(%) 75%
```

`network/mongodb-0` was the clear outlier:

```text
network/mongodb-0  10824Mi
```

The `network` namespace total was ~11.7Gi, mostly MongoDB. The live StatefulSet used `mongo:3.6` with no resources and no explicit WiredTiger cache cap:

```yaml
resources: {}
```

## Root cause

This MongoDB backs Unifi. MongoDB/WiredTiger will use large cache by default when unconstrained by a container limit. For this Unifi DB the actual data was small (~90Mi on disk), so ~10.8Gi RSS was cache bloat, not necessary working set.

## Safe fix workflow

1. Confirm consumers:
   ```bash
   export KUBECONFIG=/home/erix/.kube/config
   K=/home/erix/.local/bin/kubectl
   F=/home/erix/.local/bin/flux
   $K top nodes
   $K top pods -A --sort-by=memory
   $K top pod -A --containers --sort-by=memory | head -40
   ```

2. Inspect the live MongoDB spec and DB sanity:
   ```bash
   $K -n network get sts mongodb -o yaml | sed -n '1,220p'
   $K -n network exec mongodb-0 -- mongo --quiet --eval 'db.adminCommand({listDatabases:1}).databases.map(d=>({name:d.name,sizeOnDisk:d.sizeOnDisk}))'
   $K -n network exec mongodb-0 -- mongo unifi --quiet --eval 'print("admin=" + db.admin.count()); print("device=" + db.device.count())'
   ```

3. Before restart, create a compressed mongodump archive without dumping contents into chat:
   ```bash
   mkdir -p /home/erix/backups/unifi-mongo
   backup=/home/erix/backups/unifi-mongo/unifi-mongo-pre-cache-cap-$(date -u +%Y%m%dT%H%M%SZ).archive.gz
   $K -n network exec mongodb-0 -- mongodump --archive --gzip > "$backup"
   ls -lh "$backup"
   ```

4. Patch `apps/unifi/mongo/mongo-deployment.yaml`:
   ```yaml
   containers:
   - name: mongodb
     image: mongo:3.6
     args:
     - --wiredTigerCacheSizeGB
     - "1"
     resources:
       requests:
         cpu: 50m
         memory: 512Mi
       limits:
         memory: 2Gi
   ```

5. Dry-run, commit, push, reconcile:
   ```bash
   cd /home/erix/Projects/homelab
   $K apply --dry-run=client -k apps/unifi
   git add apps/unifi/mongo/mongo-deployment.yaml
   git commit -m "fix: cap Unifi MongoDB memory"
   git push origin main
   $F reconcile source git flux-system
   $F reconcile kustomization apps --with-source
   $F reconcile kustomization unifi --with-source
   ```

6. Verify rollout and memory:
   ```bash
   $K -n network rollout status statefulset/mongodb --timeout=300s
   $K -n network wait --for=condition=Ready pod/mongodb-0 --timeout=180s
   $K -n network exec mongodb-0 -- sh -c 'ps -o pid,args -C mongod || ps aux | grep [m]ongod'
   $K -n network exec mongodb-0 -- mongo --quiet --eval 'var c=db.serverStatus().wiredTiger.cache; printjson({maxBytesConfigured:c["maximum bytes configured"], bytesCurrentlyInCache:c["bytes currently in the cache"], trackedDirtyBytes:c["tracked dirty bytes in the cache"]}); db=db.getSiblingDB("unifi"); print("admin=" + db.admin.count()); print("device=" + db.device.count())'
   $K top pod -n network --sort-by=memory
   $K top nodes
   curl -k -sS --max-time 10 -o /tmp/unifi_check.out -w '%{http_code}\n' -H 'Host: unifi.erix-homelab.site' https://192.168.11.200/status
   ```

Expected result from the observed fix:

- `mongod --wiredTigerCacheSizeGB 1 --bind_ip_all`
- `maxBytesConfigured: 1073741824`
- `network/mongodb-0` dropped from ~10824Mi to ~71Mi immediately after restart.
- Node memory dropped from ~75% to ~38%.
- Unifi `/status` returned HTTP 200 with `up: true`.

## Pitfalls

- Do not jump directly to MongoDB major-version upgrades while fixing memory pressure. The repo has an upgrade plan, but MongoDB 3.6 → newer versions requires incremental FCV-aware upgrades. A cache cap is a safer, targeted fix.
- Always back up before restarting database pods, even if the change is “only” args/resources.
- If memory grows over time, confirm actual cache usage and Unifi health before lowering below 1Gi; Unifi itself stayed around ~930Mi in the observed environment.