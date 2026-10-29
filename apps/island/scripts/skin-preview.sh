#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Separate bundle, defaults and local server; the installed app stays untouched.
APP="$ROOT/verification/skins-v2/柚子岛皮肤预览.app"
if [[ ! -x "$APP/Contents/MacOS/YuIsland" ]]; then
  echo '请先运行 scripts/build.sh 与 scripts/package-skin-preview.sh。' >&2
  exit 1
fi
open -na "$APP" --args --skin-preview
for attempt in {1..30}; do
  if curl --silent --fail 'http://127.0.0.1:18776/skins.json' > /dev/null; then
    open 'http://127.0.0.1:18776/#skins'
    exit 0
  fi
  sleep 0.2
done
echo '预览窗口已打开，网页设置尚未就绪，可从岛内齿轮打开。' >&2
