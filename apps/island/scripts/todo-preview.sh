#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/verification/todos/柚子岛待办预览.app"
[[ -x "$APP/Contents/MacOS/YuIsland" ]] || { echo '请先构建并运行 scripts/package-todo-preview.sh' >&2; exit 1; }
open -na "$APP" --args --todo-preview
