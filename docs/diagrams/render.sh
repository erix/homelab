#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v d2 >/dev/null 2>&1; then
  echo "error: d2 is required (https://d2lang.com)" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert is required to generate PNG assets" >&2
  exit 1
fi

render_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/homelab-d2.XXXXXX")"
trap 'rm -rf "$render_tmp_dir"' EXIT

for source in architecture network-endpoints storage-architecture tailscale-services; do
  echo "Rendering ${source}.d2"
  svg_path="${render_tmp_dir}/${source}.svg"
  d2 --layout=dagre --theme=0 --pad=40 "${source}.d2" "$svg_path"
  rsvg-convert --format=png --output="${source}.png" "$svg_path"
done

echo "Rendered all diagrams to ${SCRIPT_DIR}"
