#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
CACHE="$ROOT/.build/dot-auth-helper"
mkdir -p "$CACHE"
HASH="$(shasum -a 256 "$ROOT/DotAuthHelper/main.swift" | cut -d ' ' -f 1)"
if [[ ! -x "$CACHE/feishu-dot-auth" || ! -f "$CACHE/source.sha256" || "$(cat "$CACHE/source.sha256")" != "$HASH" ]]; then
    swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macosx15.0" "$ROOT/DotAuthHelper/main.swift" -o "$CACHE/feishu-dot-auth"
    codesign --force --sign - --identifier local.zaizhi.feishu-island.dot-auth "$CACHE/feishu-dot-auth"
    echo "$HASH" > "$CACHE/source.sha256"
fi
codesign --verify --strict "$CACHE/feishu-dot-auth"
