# Migration to Calibre-Web-Automated (CWA)

## Overview

This guide helps you migrate from the standard Calibre + Calibre-Web setup to Calibre-Web-Automated, which provides streamlined book acquisition and automation features.

## What's Changing

### Before (Current Setup)
- **Calibre**: Full desktop application at 192.168.11.209:8080
- **Calibre-Web**: Lightweight web interface at 192.168.11.210:8083  
- **Manual Process**: Upload books through Calibre web interface

### After (CWA Setup)
- **Calibre-Web-Automated**: All-in-one solution at 192.168.11.211:8083
- **Auto-Import**: Drop books in ingest folder for automatic processing
- **Format Conversion**: Automatic conversion of 28+ formats to EPUB
- **Enhanced Web UI**: Modern interface with automation controls

## Migration Steps

### Step 1: Deploy Calibre-Web-Automated

```bash
# Create PVCs first
kubectl apply -f /Users/eriksimko/github/homelab/k3s/apps/calibre/calibre-web-automated-pvc.yaml

# Deploy the application
kubectl apply -f /Users/eriksimko/github/homelab/k3s/apps/calibre/calibre-web-automated.yaml
```

### Step 2: Initial Configuration

1. Access CWA at `https://books-automated.erix-homelab.site` or `192.168.11.211:8083`
2. Complete initial setup wizard
3. Point to existing Calibre library at `/calibre-library`
4. Configure CWA settings in the web interface

### Step 3: Configure Auto-Import

1. In CWA Settings, enable auto-import from `/cwa-book-ingest`
2. Configure format conversion preferences (recommend EPUB)
3. Set up file organization rules
4. Enable duplicate book merging (non-destructive)

### Step 4: Test Auto-Import Workflow

1. Upload a test book to the ingest folder:
   ```bash
   # Copy a test book to the ingest volume
   kubectl cp test-book.epub calibre-web-automated-pod:/cwa-book-ingest/
   ```
2. Verify automatic processing and library addition
3. Check format conversion and metadata enhancement

### Step 5: Migration from Current Calibre-Web (Optional)

If you want to migrate settings from the existing Calibre-Web:

1. **Backup current config**:
   ```bash
   kubectl cp calibre-web-pod:/config ./calibre-web-backup
   ```

2. **Copy relevant settings** to CWA config directory (user preferences, custom settings)

3. **Test thoroughly** before decommissioning old setup

## File Locations

- **Calibre Library**: `/calibre-library` (shared NFS volume `pvc-books-nfs`)
- **CWA Config**: `/config` (new PVC `calibre-web-automated-pvc`)
- **Auto-Ingest**: `/cwa-book-ingest` (new PVC `calibre-ingest-pvc`)

## Access Points

- **Web Interface**: `https://books-automated.erix-homelab.site`
- **Direct IP**: `192.168.11.211:8083`
- **Ingest Folder**: Available via file manager or direct volume mount

## Automation Features

### Auto-Import
- Drop any supported book format in `/cwa-book-ingest`
- Automatic detection and processing
- Conversion to EPUB for optimal compatibility
- Metadata enhancement and organization

### Format Support
- Input: 28+ formats including PDF, MOBI, AZW3, TXT, HTML, etc.
- Output: EPUB (recommended) or configurable
- Lossless conversion with metadata preservation

### Duplicate Handling
- Non-destructive merging of duplicate books
- Multiple formats per book entry
- Intelligent metadata consolidation

## Troubleshooting

### Common Issues

1. **Books not appearing**: Check ingest folder permissions and CWA logs
2. **Conversion failures**: Verify format support and disk space
3. **Metadata issues**: Configure OpenLibrary as primary source

### Monitoring

```bash
# Check CWA pod status
kubectl get pods -l app=calibre-web-automated

# View CWA logs
kubectl logs -f deployment/calibre-web-automated

# Check PVC status
kubectl get pvc | grep calibre
```

## Rollback Plan

If needed to rollback to the original setup:

1. Stop CWA deployment:
   ```bash
   kubectl scale deployment calibre-web-automated --replicas=0
   ```

2. Re-enable original Calibre-Web:
   ```bash
   kubectl scale deployment calibre-web --replicas=1
   ```

3. Books remain untouched in shared NFS volume

## Benefits After Migration

- **Streamlined Workflow**: Drop books in folder instead of manual upload
- **Format Standardization**: All books converted to EPUB automatically  
- **Enhanced Metadata**: Better book information and organization
- **Modern Interface**: Improved web UI with automation controls
- **Backup Features**: Automatic compression and backup management
- **Notification Support**: Integration with Telegram, Gotify, etc.

## Next Steps

After successful migration:

1. Set up automated book sources (RSS feeds, download integration)
2. Configure notification systems
3. Set up automated backup schedules
4. Consider integrating with book discovery tools

## Support

- **Project Documentation**: [Calibre-Web-Automated GitHub](https://github.com/crocodilestick/Calibre-Web-Automated)
- **Community Support**: Check GitHub issues and discussions
- **Local Logs**: Monitor Kubernetes logs for troubleshooting