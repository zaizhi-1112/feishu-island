#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
OUTPUT="$ROOT/.build/account-memory-check"
mkdir -p "$ROOT/.build"
swiftc -O -sdk "$SDK" "$ROOT/Sources/IslandShell/Feishu/AccountReader.swift" "$ROOT/Tests/AccountMemoryChecks/Stubs.swift" "$ROOT/Tests/AccountMemoryChecks/main.swift" -o "$OUTPUT"
ISLAND_MEMORY_ENFORCE=1 "$OUTPUT" "$ROOT/Tests/AccountMemoryChecks/fake-cli.py"
