# Immich Remote Machine Learning

Use this when Immich logs show the machine learning server is unhealthy, or when moving Immich ML work off the k3s node to a remote CPU/GPU host.

## Durable finding from session

Immich can be configured in the Admin UI to use an external ML endpoint such as:

```text
http://192.168.1.90:3003
```

If the server logs show `Machine learning server became unhealthy (<url>)`, verify network reachability from both:

1. the k3s host (`kaiburg`), and
2. inside the `immich-server` pod.

Do not assume the local `immich-machine-learning` Deployment is usable as a fallback unless a Kubernetes Service exists for it. In the observed manifests, the Deployment existed but `service/immich-machine-learning` did not, so `http://immich-machine-learning:3003` would not resolve.

## Inspection commands

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl
F=/home/erix/.local/bin/flux

$K -n immich get deploy,statefulset,pod,svc,ingress -o wide
$K -n immich logs deploy/immich-machine-learning --tail=80
$K -n immich logs deploy/immich-server --tail=300 | grep -iE 'machine|smart|clip|recognition|ml' | tail -80
$K -n immich get svc immich-machine-learning -o yaml || true
$K -n immich get endpointslices -l kubernetes.io/service-name=immich-machine-learning -o wide || true
```

Reachability from host:

```bash
curl -fsS -m 3 http://<remote-ml-host>:3003/ping
nc -vz <remote-ml-host> 3003
ip route get <remote-ml-host>
ip neigh show <remote-ml-host>
```

Reachability from Immich server pod:

```bash
POD=$($K -n immich get pod -l app=immich-server -o jsonpath='{.items[0].metadata.name}')
$K -n immich exec "$POD" -- sh -lc 'node -e "fetch(\"http://<remote-ml-host>:3003/ping\",{signal:AbortSignal.timeout(3000)}).then(async r=>{console.log(r.status); console.log(await r.text())}).catch(e=>{console.error(e.message); process.exit(1)})"'
```

## Recommended topology

```text
Immich server in k3s
        |
        | HTTP :3003 over LAN/Tailscale
        v
Remote CPU/GPU host
  └─ immich-machine-learning container
     ├─ hardware acceleration image variant when applicable
     └─ persistent /cache volume for model cache
```

Run only the ML container on the remote host; keep Postgres, Redis, and Immich server in k3s.

## Remote host container sketch

NVIDIA example:

```yaml
services:
  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:<immich-version>-cuda
    container_name: immich-machine-learning
    restart: unless-stopped
    ports:
      - "3003:3003"
    volumes:
      - ./model-cache:/cache
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

Use the same Immich version family as the server where possible. For CPU-only hosts, omit the CUDA suffix and GPU device reservation.

## GitOps fallback improvement

If leaving a local ML Deployment in k3s, add a Service so the local fallback URL works:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: immich-machine-learning
  namespace: immich
spec:
  selector:
    app: immich-machine-learning
  ports:
    - port: 3003
      targetPort: 3003
```

Then fallback ML URL can be:

```text
http://immich-machine-learning:3003
```

## Verification checklist

- [ ] Remote host answers `curl http://<host>:3003/ping` locally.
- [ ] `kaiburg` can reach `<host>:3003`.
- [ ] `immich-server` pod can reach `<host>:3003`.
- [ ] Immich Admin UI Machine Learning URL points to the intended endpoint.
- [ ] Server logs stop reporting `Machine learning server became unhealthy`.
- [ ] Smart search / face recognition jobs can run after the endpoint is healthy.
- [ ] If relying on local fallback, `service/immich-machine-learning` exists and has endpoints.
