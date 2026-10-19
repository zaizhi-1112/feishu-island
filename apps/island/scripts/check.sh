#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ISLAND_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
swift run --sdk "$SDK" IslandChecks
