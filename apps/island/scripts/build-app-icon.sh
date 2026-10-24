#!/bin/bash
# Convert the user-approved original artwork; no design changes or personal assets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Distribution/brand/work-island-original.png"
mkdir -p "$ROOT/.build"
STAGE="$(mktemp -d "$ROOT/.build/app-icon.XXXXXX")"
ICONSET="$STAGE/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
sips -z 256 256 "$SOURCE" --out "$ROOT/Distribution/site/icon.png" >/dev/null
printf 'Application and portal icons generated from the approved artwork.\n'
