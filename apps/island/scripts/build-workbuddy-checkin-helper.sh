#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
DIR="$ROOT/.build/workbuddy-checkin-helper"
mkdir -p "$DIR"
HASH="$(shasum -a 256 "$ROOT/scripts/workbuddy-checkin-helper.swift" "$ROOT/Sources/IslandShell/Agents/WorkBuddyDailyFlow.swift" | shasum -a 256 | cut -d' ' -f1)"
if [[ -x "$DIR/workbuddy-checkin-helper" && -f "$DIR/source.sha256" && "$(cat "$DIR/source.sha256")" == "$HASH" ]]; then
  codesign --verify --strict "$DIR/workbuddy-checkin-helper"
else
  cp "$ROOT/scripts/workbuddy-checkin-helper.swift" "$DIR/main.swift"
  swiftc -O -sdk "$SDK" "$ROOT/Sources/IslandShell/Agents/WorkBuddyDailyFlow.swift" "$DIR/main.swift" -o "$DIR/workbuddy-checkin-helper"
  codesign --force --sign - --identifier local.zaizhi.feishu-island.workbuddy-checkin "$DIR/workbuddy-checkin-helper"
  printf '%s' "$HASH" > "$DIR/source.sha256"
fi
