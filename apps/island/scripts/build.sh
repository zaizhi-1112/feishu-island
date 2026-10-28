#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
export SWIFT_MODULECACHE_PATH="$CLANG_MODULE_CACHE_PATH"
cd "$ROOT"
# SDK 27's SwiftUI macros require an Xcode plugin not shipped with this Mac's CLT.
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
if [[ ! -d "$SDK" ]]; then
    echo "SDK not found: $SDK. Set ISLAND_SDK to a compatible installed macOS SDK." >&2
    exit 1
fi
CONFIG="${ISLAND_CONFIGURATION:-release}"
SCRATCH="${ISLAND_SCRATCH_PATH:-$ROOT/.build}"
swift build --disable-sandbox --scratch-path "$SCRATCH" -j 2 --sdk "$SDK" -c "$CONFIG" --product YuIsland
BIN_DIR="$(swift build --disable-sandbox --scratch-path "$SCRATCH" --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
APP="${ISLAND_APP_OUTPUT:-$ROOT/dist/一切在岛.app}"
[[ "$APP" = /* && "$APP" = *.app ]] || { echo 'ISLAND_APP_OUTPUT 必须是绝对 .app 路径' >&2; exit 1; }
if [[ -n "${ISLAND_APP_OUTPUT:-}" && ( -e "$APP" || -L "$APP" ) ]]; then
    echo '独立构建路径必须尚不存在，不覆盖已安装或已运行的应用。' >&2; exit 1
fi
if pgrep -f "^$APP/Contents/MacOS/YuIsland$" >/dev/null; then
    echo '工作岛正在运行，请手动退出后再构建。不会替换运行中的程序。' >&2; exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ISLAND_LARK_CLI="${ISLAND_LARK_CLI:-$(command -v lark-cli || true)}"
if [[ -z "$ISLAND_LARK_CLI" || ! -x "$ISLAND_LARK_CLI" ]]; then
    echo '完整产品必须内置官方lark-cli。请设置ISLAND_LARK_CLI为官方可执行文件路径后重建。' >&2
    exit 1
fi
if [[ -n "$ISLAND_LARK_CLI" ]]; then
    [[ -x "$ISLAND_LARK_CLI" ]] || { echo 'ISLAND_LARK_CLI 必须是官方可执行文件' >&2; exit 1; }
    mkdir -p "$APP/Contents/Helpers"
    cp "$ISLAND_LARK_CLI" "$APP/Contents/Helpers/lark-cli"
    cp "$ROOT/Vendor/LarkCLI/LICENSE" "$APP/Contents/Resources/LarkCLI-LICENSE"
fi
mkdir -p "$APP/Contents/Helpers"
if [[ -n "${ISLAND_HUB_HELPER:-}" ]]; then
    [[ -x "$ISLAND_HUB_HELPER" ]] || { echo 'ISLAND_HUB_HELPER 必须是已核验的可执行文件' >&2; exit 1; }
    codesign --verify --strict "$ISLAND_HUB_HELPER"
    cp "$ISLAND_HUB_HELPER" "$APP/Contents/Helpers/feishu-hub-helper"
else
    ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-hub-helper.sh"
    cp "$ROOT/.build/hub-helper/feishu-hub-helper" "$APP/Contents/Helpers/feishu-hub-helper"
fi
cp "$BIN_DIR/YuIsland" "$APP/Contents/MacOS/YuIsland"
if [[ -n "${ISLAND_AGENT_STATUS_HELPER:-}" ]]; then
    [[ -x "$ISLAND_AGENT_STATUS_HELPER" ]] || { echo 'ISLAND_AGENT_STATUS_HELPER 必须是已核验的可执行文件' >&2; exit 1; }
    codesign --verify --strict "$ISLAND_AGENT_STATUS_HELPER"
    cp "$ISLAND_AGENT_STATUS_HELPER" "$APP/Contents/Helpers/agent-status-helper"
else
    swiftc -O -sdk "$SDK" "$ROOT/Sources/IslandShell/Agents/AgentHookProtocol.swift" "$ROOT/Sources/IslandShell/Agents/AgentModel.swift" "$ROOT/Sources/IslandShell/Agents/AgentBridge.swift" "$ROOT/Sources/IslandShell/Agents/WorkBuddyPendingTool.swift" "$ROOT/scripts/agent-status-helper.swift" -o "$APP/Contents/Helpers/agent-status-helper"
    codesign --force --sign - "$APP/Contents/Helpers/agent-status-helper"
fi
mkdir -p "$APP/Contents/Resources/SettingsWeb"
cp "$ROOT/SettingsWeb/dist/"* "$APP/Contents/Resources/SettingsWeb/"
mkdir -p "$APP/Contents/Resources/LOLPing"
cp "$ROOT/Resources/LOLPing/"* "$APP/Contents/Resources/LOLPing/"
cp "$ROOT/Distribution/开始使用.html" "$APP/Contents/Resources/开始使用.html"
mkdir -p "$APP/Contents/Resources/ScreenReminder"
for asset in rick-portal.mov SOURCE.txt; do
    cp "$ROOT/Resources/ScreenReminder/$asset" "$APP/Contents/Resources/ScreenReminder/"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Vendor/OpenNook/LICENSE" "$APP/Contents/Resources/OpenNook-LICENSE"
cp "$ROOT/Vendor/OpenNook/LICENSE-MIT-NOOKSURFACE" "$APP/Contents/Resources/NookSurface-LICENSE"
cp "$ROOT/Vendor/OpenNook/NOTICE.md" "$APP/Contents/Resources/OpenNook-NOTICE.md"
cp -R "$ROOT/Vendor/OpenNook/ThirdPartyLicenses" "$APP/Contents/Resources/"
bash "$ROOT/scripts/build-app-icon.sh"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
