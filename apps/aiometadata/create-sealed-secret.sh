#!/bin/bash
# Script to create a SealedSecret for aiometadata

set -e

echo "Creating SealedSecret for aiometadata..."
echo ""
echo "This script will prompt you for the required API keys and create a sealed secret."
echo ""

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed"
    echo "Install it with: brew install kubeseal"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl get ns &> /dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Prompt for required TMDB API key
read -p "Enter your TMDB API key (required): " TMDB_API

if [ -z "$TMDB_API" ]; then
    echo "Error: TMDB API key is required"
    exit 1
fi

# Optional API keys
read -p "Enter TVDB API key (optional, press Enter to skip): " TVDB_API_KEY
read -p "Enter Fanart API key (optional, press Enter to skip): " FANART_API_KEY
read -p "Enter RPDB API key (optional, press Enter to skip): " RPDB_API_KEY
read -p "Enter MDBList API key (optional, press Enter to skip): " MDBLIST_API_KEY
read -p "Enter Gemini API key (optional, press Enter to skip): " GEMINI_API_KEY
read -p "Enter Admin key (optional, press Enter to skip): " ADMIN_KEY
read -p "Enter Addon password (optional, press Enter to skip): " ADDON_PASSWORD

# Create temporary secret manifest
cat > /tmp/aiometadata-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: aiometadata-secret
  namespace: stremio
type: Opaque
stringData:
  TMDB_API: "${TMDB_API}"
EOF

# Add optional keys if provided
[ ! -z "$TVDB_API_KEY" ] && echo "  TVDB_API_KEY: \"${TVDB_API_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$FANART_API_KEY" ] && echo "  FANART_API_KEY: \"${FANART_API_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$RPDB_API_KEY" ] && echo "  RPDB_API_KEY: \"${RPDB_API_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$MDBLIST_API_KEY" ] && echo "  MDBLIST_API_KEY: \"${MDBLIST_API_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$GEMINI_API_KEY" ] && echo "  GEMINI_API_KEY: \"${GEMINI_API_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$ADMIN_KEY" ] && echo "  ADMIN_KEY: \"${ADMIN_KEY}\"" >> /tmp/aiometadata-secret.yaml
[ ! -z "$ADDON_PASSWORD" ] && echo "  ADDON_PASSWORD: \"${ADDON_PASSWORD}\"" >> /tmp/aiometadata-secret.yaml

# Seal the secret
echo ""
echo "Sealing secret..."
kubeseal --format yaml < /tmp/aiometadata-secret.yaml > aiometadata-sealed-secret.yaml

# Clean up temporary file
rm /tmp/aiometadata-secret.yaml

echo ""
echo "✓ Sealed secret created: aiometadata-sealed-secret.yaml"
echo ""
echo "You can now safely commit this file to git and apply it with:"
echo "  kubectl apply -f apps/aiometadata/aiometadata-sealed-secret.yaml"
