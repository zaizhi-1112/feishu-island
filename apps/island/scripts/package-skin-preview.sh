#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/柚子岛.app"
APP="$ROOT/verification/skins-v2/柚子岛皮肤预览.app"
[[ -x "$SOURCE/Contents/MacOS/YuIsland" ]] || { echo '请先运行 scripts/build.sh' >&2; exit 1; }
ditto "$SOURCE" "$APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.youzi.island.skin-preview' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 柚子岛皮肤预览' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 柚子岛皮肤预览' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Preview: %s\n' "$APP"
