# AIOStreams - Stremio Super-Addon

A Stremio super-addon that consolidates multiple addons and debrid services into a single, highly customizable interface.

## Features

- **Unified Results**: Combines streams from multiple addons with consistent sorting
- **Built-in Addons**: 10+ integrated addons (Knaben, Zilean, AnimeTosho, TorBox, Jackett, Prowlarr, etc.)
- **Advanced Filtering**: Resolution, quality, HDR, audio, language, seeders
- **Custom Formatting**: Template system for stream title display
- **Catalog Management**: Rename, reorder, disable catalogs
- **Proxy Support**: MediaFlow Proxy or StremThru integration

## Deployment Information

- **Image**: `ghcr.io/viren070/aiostreams:latest`
- **Port**: 3000
- **URL**: https://aiostreams.erix-homelab.site
- **Storage**: 5Gi for configuration and cache data

## Configuration

### Required Environment Variables

- `SECRET_KEY`: 64-character hexadecimal secret key (REQUIRED for encryption)

### Optional Environment Variables

- `ADDON_PROXY`: Proxy URL for bypassing IP restrictions (e.g., `http://gluetun:8080`)
- `ADDON_PROXY_CONFIG`: Proxy rules (e.g., `*:false,*.strem.fun:true`)
- `BUILTIN_BITMAGNET_URL`: Enable Bitmagnet addon (requires Bitmagnet instance)

## Deployment Steps

1. **The sealed secret needs to be created**:
   ```bash
   # Seal the secret
   kubeseal --format yaml < apps/aiostreams/aiostreams-secret.yaml > apps/aiostreams/aiostreams-sealed-secret.yaml
   ```

2. **Apply all manifests**:
   ```bash
   kubectl apply -f apps/aiostreams/
   ```

3. **Verify deployment**:
   ```bash
   kubectl get pods -n stremio -l app=aiostreams
   kubectl get ingress -n stremio aiostreams
   ```

4. **Check logs**:
   ```bash
   kubectl logs -n stremio -f deployment/aiostreams
   ```

5. **Access the configuration UI**:
   ```
   https://aiostreams.erix-homelab.site/stremio/configure
   ```

## Storage

- **aiostreams-data**: 5Gi Longhorn volume for configuration and cache

## Resources

- **aiostreams**:
  - Requests: 256Mi RAM, 250m CPU
  - Limits: 1Gi RAM, 1000m CPU

## Health Checks

- **Readiness**: HTTP check on `/` endpoint (10s delay)
- **Liveness**: HTTP check on `/` endpoint (30s delay)

## Configuration Workflow

1. Access https://aiostreams.erix-homelab.site/stremio/configure
2. Enable desired addons (Torrentio, Prowlarr, Jackett, etc.)
3. Add debrid service API keys (Real-Debrid, Premiumize, etc.)
4. Configure filtering and sorting preferences
5. Customize stream title formatting
6. Click "Install" to add to Stremio

## Built-in Addons

- **Torrent Search**: Knaben, Zilean, AnimeTosho, TorBox Search, Bitmagnet
- **Indexer Managers**: Jackett, Prowlarr, NZBHydra
- **Protocols**: Newznab, Torznab
- **Cloud Storage**: GDrive

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod -n stremio <pod-name>
kubectl logs -n stremio <pod-name>
```

### Secret key issues
The SECRET_KEY must be exactly 64 hexadecimal characters. Check the sealed secret is applied correctly.

### Ingress not working
```bash
# Check ingress status
kubectl describe ingress -n stremio aiostreams

# Verify DNS resolves
nslookup aiostreams.erix-homelab.site

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

## Upgrading

```bash
# Update to latest image
kubectl rollout restart deployment/aiostreams -n stremio

# Check rollout status
kubectl rollout status deployment/aiostreams -n stremio
```

## Links

- **Repository**: https://github.com/Viren070/AIOStreams
- **Docker Hub**: https://hub.docker.com/r/viren070/aiostreams
- **GHCR**: https://github.com/Viren070/AIOStreams/pkgs/container/aiostreams
- **Documentation**: https://github.com/Viren070/AIOStreams/wiki
