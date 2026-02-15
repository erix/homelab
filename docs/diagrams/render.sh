#!/bin/bash
# Render all D2 diagrams to SVG

set -e

echo "Rendering D2 diagrams..."
echo

d2 architecture.d2 architecture.svg
echo "✓ architecture.svg generated"

d2 network-endpoints.d2 network-endpoints.svg
echo "✓ network-endpoints.svg generated"

d2 tailscale-services.d2 tailscale-services.svg
echo "✓ tailscale-services.svg generated"

d2 storage-architecture.d2 storage-architecture.svg
echo "✓ storage-architecture.svg generated"

echo
echo "Done! All diagrams rendered to SVG."
echo
echo "These diagrams are used in:"
echo "  - ../../README.md (main homelab README)"
echo "  - ../../apps/ib-gateway/README.md (IB Gateway)"
