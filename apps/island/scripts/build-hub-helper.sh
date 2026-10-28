#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
CACHE="$ROOT/.build/hub-helper"
mkdir -p "$CACHE"
HASH="$(cat "$ROOT/HubHelper/HubBackend.swift" "$ROOT/HubHelper/HubHelperMain.swift" "$ROOT/Sources/IslandShell/Workspace/HubTypes.swift" | shasum -a 256 | cut -d ' ' -f 1)"
if [[ ! -x "$CACHE/feishu-hub-helper" || ! -f "$CACHE/source.sha256" || "$(cat "$CACHE/source.sha256")" != "$HASH" ]]; then
    swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macosx15.0" "$ROOT/HubHelper/HubBackend.swift" "$ROOT/HubHelper/HubHelperMain.swift" "$ROOT/Sources/IslandShell/Workspace/HubTypes.swift" -o "$CACHE/feishu-hub-helper"
    codesign --force --sign - --identifier local.zaizhi.feishu-island.hub-helper "$CACHE/feishu-hub-helper"
    echo "$HASH" > "$CACHE/source.sha256"
fi
codesign --verify --strict "$CACHE/feishu-hub-helper"
