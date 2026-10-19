#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-web}" in
 web) npm test --prefix "$ROOT/apps/danmu/Web"; npm test --prefix "$ROOT/apps/danmu/Desktop" ;;
 island|island-reader)
  # Prefer the SDK selected by this developer, never another person's machine path.
  export ISLAND_SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
  if [[ "$1" == island ]]; then bash "$ROOT/apps/island/scripts/check.sh"; else bash "$ROOT/apps/island/scripts/check-feishu.sh"; fi ;;
 mcp)
  TEST_DIR="$(mktemp -d -t feishu-island-mcp)"
  swiftc "$ROOT/apps/danmu/scripts/AppearanceMCP.swift" "$ROOT/apps/danmu/Tests/AppearanceMCPTests.swift" -o "$TEST_DIR/check"
  "$TEST_DIR/check" ;;
 *) echo '用法：bash scripts/check.sh web|island|island-reader|mcp' >&2; exit 2 ;;
esac
