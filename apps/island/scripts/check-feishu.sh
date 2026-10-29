#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
TEST_DIR="$(mktemp -d -t island-feishu-check)"
export DANMU_TEST_STATE="$TEST_DIR/state.json"
swift build --disable-sandbox --sdk "$SDK" -j 2 --product FeishuReaderChecks
".build/debug/FeishuReaderChecks"
