#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
TEST_DIR="$(mktemp -d -t island-feishu-check)"
export DANMU_TEST_STATE="$TEST_DIR/state.json"
swiftc -sdk "$SDK" Sources/IslandShell/Feishu/AccountReader.swift Sources/IslandShell/Feishu/FeishuTransport.swift Sources/IslandShell/Feishu/ServerClock.swift Sources/IslandShell/Feishu/FeishuMessage.swift Tests/FeishuReaderChecks/main.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
