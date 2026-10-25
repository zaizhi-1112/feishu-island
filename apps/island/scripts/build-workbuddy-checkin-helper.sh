#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
DIR="$ROOT/.build/workbuddy-checkin-helper"
APP="$DIR/WorkBuddyCheckin.app"
mkdir -p "$DIR"
HASH="$(shasum -a 256 "$ROOT/scripts/workbuddy-checkin-helper.swift" "$ROOT/Sources/IslandShell/Agents/WorkBuddyDailyFlow.swift" "$ROOT/scripts/build-workbuddy-checkin-helper.sh" | cut -d' ' -f1 | shasum -a 256 | cut -d' ' -f1)"
if [[ -x "$APP/Contents/MacOS/workbuddy-checkin-helper" && -f "$DIR/app-source.sha256" && "$(cat "$DIR/app-source.sha256")" == "$HASH" ]]; then
  codesign --verify --strict "$APP"
else
  mkdir -p "$APP/Contents/MacOS"
  cp "$ROOT/scripts/workbuddy-checkin-helper.swift" "$DIR/main.swift"
  swiftc -O -sdk "$SDK" "$ROOT/Sources/IslandShell/Agents/WorkBuddyDailyFlow.swift" "$DIR/main.swift" -o "$APP/Contents/MacOS/workbuddy-checkin-helper"
  python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:plistlib.dump({'CFBundleIdentifier':'local.zaizhi.feishu-island.workbuddy-checkin','CFBundleExecutable':'workbuddy-checkin-helper','CFBundleName':'工作岛签到','CFBundleDisplayName':'工作岛签到','CFBundlePackageType':'APPL','CFBundleVersion':'1','LSUIElement':True,'LSMinimumSystemVersion':'15.0'},f)
PY
  codesign --force --sign - "$APP"
  printf '%s' "$HASH" > "$DIR/app-source.sha256"
fi
