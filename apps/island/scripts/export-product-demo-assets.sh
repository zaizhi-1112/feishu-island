#!/bin/bash
# Native UI, synthetic inputs, hidden windows. No account or desktop capture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift run -j 2 --sdk "${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}" FusionChecks --product-demo-assets
for name in feishu-compact feishu-expanded agent-idle agent-working agent-waiting agent-completed materials result; do
  cp ".build/product-demo-assets/demo-$name.png" "Distribution/site/demo-$name.png"
done
cp .build/product-demo-assets/manifest.json Distribution/brand/native-demo-manifest.json
