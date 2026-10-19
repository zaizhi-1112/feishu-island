#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# SDK 27's SwiftUI macros require an Xcode plugin not shipped with this Mac's CLT.
SDK="${ISLAND_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$SDK" ]]; then
    echo "SDK not found: $SDK. Set ISLAND_SDK to a compatible installed macOS SDK." >&2
    exit 1
fi
CONFIG="${ISLAND_CONFIGURATION:-release}"
swift build --sdk "$SDK" -c "$CONFIG" --product YuIsland
BIN_DIR="$(swift build --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
APP="$ROOT/dist/柚子岛.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/YuIsland" "$APP/Contents/MacOS/YuIsland"
mkdir -p "$APP/Contents/Resources/SettingsWeb"
cp "$ROOT/SettingsWeb/dist/"* "$APP/Contents/Resources/SettingsWeb/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Vendor/OpenNook/LICENSE" "$APP/Contents/Resources/OpenNook-LICENSE"
cp "$ROOT/Vendor/OpenNook/LICENSE-MIT-NOOKSURFACE" "$APP/Contents/Resources/NookSurface-LICENSE"
cp "$ROOT/Vendor/OpenNook/NOTICE.md" "$APP/Contents/Resources/OpenNook-NOTICE.md"
cp -R "$ROOT/Vendor/OpenNook/ThirdPartyLicenses" "$APP/Contents/Resources/"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
