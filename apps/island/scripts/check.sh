#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
# UI-only iterations do not need the historical workbench fixtures.
if [[ "${1:-}" == "layout" ]]; then
    swift run --disable-sandbox --sdk "$SDK" UnifiedProductChecks --skin-preview
    swift run --disable-sandbox --sdk "$SDK" IslandLayoutChecks "$PWD/.build/current-layout-check" --skin-preview
    exit
fi
swift run --sdk "$SDK" IslandChecks
swift run --sdk "$SDK" TodoChecks
swift run --sdk "$SDK" NavigationChecks --skin-preview

swift run --sdk "$SDK" AgentChecks
STATUS_CHECK_DIR="$(mktemp -d -t island-status-check)"
swiftc -sdk "$SDK" Sources/IslandShell/Agents/AgentHookProtocol.swift Sources/IslandShell/Agents/AgentModel.swift Sources/IslandShell/Agents/AgentBridge.swift Sources/IslandShell/Agents/WorkBuddyPendingTool.swift scripts/agent-status-helper.swift -o "$STATUS_CHECK_DIR/agent-status-helper"
python3 Tests/agent-status-helper-test.py "$STATUS_CHECK_DIR/agent-status-helper"
