#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# SDK 27's SwiftUI macros require an Xcode plugin not shipped with this Mac's CLT.
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
if [[ ! -d "$SDK" ]]; then
    echo "SDK not found: $SDK. Set ISLAND_SDK to a compatible installed macOS SDK." >&2
    exit 1
fi
CONFIG="${ISLAND_CONFIGURATION:-release}"
SCRATCH="${ISLAND_SCRATCH_PATH:-$ROOT/.build}"
swift build --scratch-path "$SCRATCH" -j 2 --sdk "$SDK" -c "$CONFIG" --product YuIsland
BIN_DIR="$(swift build --scratch-path "$SCRATCH" --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
APP="${ISLAND_APP_OUTPUT:-$ROOT/dist/飞书工作岛预览版.app}"
[[ "$APP" = /* && "$APP" = *.app ]] || { echo 'ISLAND_APP_OUTPUT 必须是绝对 .app 路径' >&2; exit 1; }
if [[ -n "${ISLAND_APP_OUTPUT:-}" && ( -e "$APP" || -L "$APP" ) ]]; then
    echo '独立构建路径必须尚不存在，不覆盖已安装或已运行的应用。' >&2; exit 1
fi
if pgrep -f "^$APP/Contents/MacOS/YuIsland$" >/dev/null; then
    echo '预览版正在运行，请手动退出后再构建。不会替换运行中的程序。' >&2; exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ -n "${ISLAND_LARK_CLI:-}" ]]; then
    [[ -x "$ISLAND_LARK_CLI" ]] || { echo 'ISLAND_LARK_CLI 必须是官方可执行文件' >&2; exit 1; }
    mkdir -p "$APP/Contents/Helpers"
    cp "$ISLAND_LARK_CLI" "$APP/Contents/Helpers/lark-cli"
    cp "$ROOT/../danmu/tools/lark-cli/LICENSE" "$APP/Contents/Resources/LarkCLI-LICENSE"
fi
ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-hub-helper.sh"
mkdir -p "$APP/Contents/Helpers"
cp "$ROOT/.build/hub-helper/feishu-hub-helper" "$APP/Contents/Helpers/feishu-hub-helper"
cp "$BIN_DIR/YuIsland" "$APP/Contents/MacOS/YuIsland"
swiftc -O -sdk "$SDK" "$ROOT/Sources/IslandShell/Agents/AgentHookProtocol.swift" "$ROOT/scripts/agent-status-helper.swift" -o "$APP/Contents/Helpers/agent-status-helper"
codesign --force --sign - "$APP/Contents/Helpers/agent-status-helper"
mkdir -p "$APP/Contents/Resources/SettingsWeb"
cp "$ROOT/SettingsWeb/dist/"* "$APP/Contents/Resources/SettingsWeb/"
mkdir -p "$APP/Contents/Resources/BrowserBridge"
cp "$ROOT/BrowserBridge/doubao-work.js" "$APP/Contents/Resources/BrowserBridge/"
mkdir -p "$APP/Contents/Resources/BrowserBridge/chrome-reader"
for asset in manifest.json popup.html popup.css popup.js extract.js; do
    cp "$ROOT/BrowserBridge/chrome-reader/$asset" "$APP/Contents/Resources/BrowserBridge/chrome-reader/"
done
mkdir -p "$APP/Contents/Resources/ScreenReminder"
for asset in rick-portal.mov SOURCE.txt; do
    cp "$ROOT/Resources/ScreenReminder/$asset" "$APP/Contents/Resources/ScreenReminder/"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Vendor/OpenNook/LICENSE" "$APP/Contents/Resources/OpenNook-LICENSE"
cp "$ROOT/Vendor/OpenNook/LICENSE-MIT-NOOKSURFACE" "$APP/Contents/Resources/NookSurface-LICENSE"
cp "$ROOT/Vendor/OpenNook/NOTICE.md" "$APP/Contents/Resources/OpenNook-NOTICE.md"
cp -R "$ROOT/Vendor/OpenNook/ThirdPartyLicenses" "$APP/Contents/Resources/"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-dot-auth-helper.sh"
cp "$ROOT/.build/dot-auth-helper/feishu-dot-auth" "$APP/Contents/Helpers/feishu-dot-auth"
if [[ -x "$ROOT/.build/tunnel-client/unpacked/tunnel-client" ]]; then
    # Optional private Dot transport. Never packages an API key, project grant or runtime config.
    [[ "$(shasum -a 256 "$ROOT/.build/tunnel-client/unpacked/tunnel-client" | cut -d ' ' -f 1)" == 'd8f165d8175fa9f813a113b6ef434aed25a384f765a69b3709228704e5347474' ]] || { echo 'Tunnel client checksum mismatch' >&2; exit 1; }
    ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-tunnel-helper.sh"
    cp "$ROOT/.build/tunnel-auth-helper/feishu-tunnel-auth" "$APP/Contents/Helpers/feishu-tunnel-auth"
    cp "$ROOT/.build/tunnel-client/unpacked/tunnel-client" "$APP/Contents/Helpers/tunnel-client"
    mkdir -p "$APP/Contents/Resources/TunnelClientLicenses"
    cp "$ROOT/.build/tunnel-client/unpacked/LICENSE" "$ROOT/.build/tunnel-client/unpacked/NOTICE" "$ROOT/.build/tunnel-client/unpacked/"*-licenses.txt "$APP/Contents/Resources/TunnelClientLicenses/"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
