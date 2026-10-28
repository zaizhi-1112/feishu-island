#!/bin/bash
# Build consistent app and portal icons from the user-selected cloud mascot artwork.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/AppIcon.png"
mkdir -p "$ROOT/.build"
STAGE="$(mktemp -d "$ROOT/.build/app-icon.XXXXXX")"
ICONSET="$STAGE/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p "$ROOT/Resources/AppIcon.iconset"
cp "$ICONSET/"*.png "$ROOT/Resources/AppIcon.iconset/"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
printf 'Application icons generated from the product artwork.\n'
