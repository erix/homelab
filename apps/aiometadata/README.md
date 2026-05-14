# AIOMetadata - Stremio Metadata Addon

A metadata aggregation service for Stremio that pulls content information from multiple sources including TMDB, TVDB, MyAnimeList, AniList, IMDb, and others.

## Deployment Information

- **Image**: `ghcr.io/cedya77/aiometadata:latest@sha256:1dbf878e225ef78d60e4fcd44f0a7bd18127dc36d156eb891dec1a08b202a54f`
- **Port**: 3232
- **URL**: https://aiometadata.erix-homelab.site
- **Storage**: 5Gi (SQLite database) + 2Gi (Redis cache)

## Components

1. **Main Application**: AIOMetadata addon server
2. **Redis**: Cache layer for metadata and catalogs
3. **SQLite Database**: Default database (stored in PVC)

## Configuration

### Sealed Secrets

This deployment uses **SealedSecrets** for secure secret management. The encrypted secrets are stored in `aiometadata-sealed-secret.yaml` and can be safely committed to git. The sealed-secrets controller in your cluster will decrypt them at runtime.

### Required Environment Variables

- `TMDB_API`: TMDB API key (REQUIRED) - Already configured in sealed secret
- `HOST_NAME`: Public URL for addon manifest - Set to aiometadata.erix-homelab.site

### Optional API Keys (Already configured in sealed secret)

- `TVDB_API_KEY`: TVDB for series/anime metadata
- `FANART_API_KEY`: Fanart.tv for logos/backgrounds
- `RPDB_API_KEY`: Rating Poster DB
- `MDBLIST_API_KEY`: MDBList catalog integration
- `GEMINI_API_KEY`: Google Gemini for AI features

### Security (Already configured in sealed secret)

- `ADMIN_KEY`: Dashboard endpoint protection
- `ADDON_PASSWORD`: Protected endpoints password

## Deployment Steps

1. **Create the stremio namespace (if it doesn't exist)**:
   ```bash
   kubectl create namespace stremio
   ```

2. **The sealed secret is already created** at `aiometadata-sealed-secret.yaml`. To update secrets in the future:
   ```bash
   # Edit the template with your API keys
   nano apps/aiometadata/aiometadata-secret-template.yaml

   # Seal it (kubeseal must be installed: brew install kubeseal)
   kubeseal --format yaml < apps/aiometadata/aiometadata-secret-template.yaml > apps/aiometadata/aiometadata-sealed-secret.yaml

   # IMPORTANT: Delete the plain secret template after sealing
   rm apps/aiometadata/aiometadata-secret-template.yaml
   ```

3. **Apply all manifests**:
   ```bash
   kubectl apply -f apps/aiometadata/
   ```

4. **Verify deployment**:
   ```bash
   kubectl get pods -n stremio -l app=aiometadata
   kubectl get pods -n stremio -l app=aiometadata-redis
   kubectl get ingress -n stremio aiometadata
   ```

5. **Check logs**:
   ```bash
   kubectl logs -n stremio -f deployment/aiometadata
   kubectl logs -n stremio -f deployment/aiometadata-redis
   ```

6. **Access the configuration UI**:
   - Open https://aiometadata.erix-homelab.site/configure
   - Set up catalogs, providers, and preferences
   - Copy the generated Stremio addon URL

## Getting TMDB API Key

1. Create a free account at https://www.themoviedb.org/
2. Go to Settings > API
3. Request an API key (choose "Developer" option)
4. Copy the "API Key (v3 auth)" value

## Storage

- **aiometadata-data**: 5Gi Longhorn volume for SQLite database
- **aiometadata-redis-data**: 2Gi Longhorn volume for Redis persistence

## Resources

- **aiometadata**:
  - Requests: 256Mi RAM, 250m CPU
  - Limits: 1Gi RAM, 1000m CPU
- **redis**:
  - Requests: 128Mi RAM, 100m CPU
  - Limits: 512Mi RAM, 500m CPU

## Health Checks

Both services have liveness and readiness probes configured:
- **aiometadata**: HTTP check on `/health` endpoint
- **redis**: Redis CLI ping command

## Cache Configuration

- **Catalog TTL**: 24 hours (86400s)
- **Metadata TTL**: 7 days (604800s)
- **Cache Warming**: Enabled on startup (essential mode)
- **Warmup Delay**: 5 minutes after startup

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n stremio <pod-name>
kubectl logs -n stremio <pod-name>
```

### Redis connection issues
```bash
# Check if Redis is running
kubectl get pods -n stremio -l app=aiometadata-redis

# Test Redis connectivity
kubectl exec -n stremio -it deployment/aiometadata-redis -- redis-cli ping
```

### Ingress not working
```bash
# Check ingress status
kubectl describe ingress -n stremio aiometadata

# Verify DNS resolves to MetalLB IP
nslookup aiometadata.erix-homelab.site

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

## Upgrading

```bash
# Update to latest image
kubectl rollout restart deployment/aiometadata -n stremio

# Check rollout status
kubectl rollout status deployment/aiometadata -n stremio
```

## Links

- **Repository**: https://github.com/cedya77/aiometadata
- **TMDB**: https://www.themoviedb.org/
- **Stremio**: https://www.stremio.com/
