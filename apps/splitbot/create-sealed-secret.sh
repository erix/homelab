#!/bin/bash
# Creates a SealedSecret for splitbot's TELEGRAM_BOT_TOKEN
set -e

if ! command -v kubeseal &>/dev/null; then
  echo "Error: kubeseal not installed"
  exit 1
fi

read -sp "Enter TELEGRAM_BOT_TOKEN: " BOT_TOKEN
echo ""

if [ -z "$BOT_TOKEN" ]; then
  echo "Error: token is required"
  exit 1
fi

cat > /tmp/splitbot-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: splitbot-secret
  namespace: splitbot
type: Opaque
stringData:
  TELEGRAM_BOT_TOKEN: "${BOT_TOKEN}"
EOF

echo "Sealing..."
kubeseal --format yaml < /tmp/splitbot-secret.yaml > splitbot-sealed-secret.yaml
rm /tmp/splitbot-secret.yaml

echo "✓ splitbot-sealed-secret.yaml created — commit it to git"
