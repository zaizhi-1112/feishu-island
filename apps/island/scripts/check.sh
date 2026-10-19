#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
swift run --sdk "$SDK" IslandChecks
