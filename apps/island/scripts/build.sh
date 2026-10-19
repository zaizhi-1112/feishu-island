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
swift build -j 2 --sdk "$SDK" -c "$CONFIG" --product YuIsland
BIN_DIR="$(swift build --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
APP="$ROOT/dist/飞书工作岛预览版.app"
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
cp "$BIN_DIR/YuIsland" "$APP/Contents/MacOS/YuIsland"
mkdir -p "$APP/Contents/Resources/SettingsWeb"
cp "$ROOT/SettingsWeb/dist/"* "$APP/Contents/Resources/SettingsWeb/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Vendor/OpenNook/LICENSE" "$APP/Contents/Resources/OpenNook-LICENSE"
cp "$ROOT/Vendor/OpenNook/LICENSE-MIT-NOOKSURFACE" "$APP/Contents/Resources/NookSurface-LICENSE"
cp "$ROOT/Vendor/OpenNook/NOTICE.md" "$APP/Contents/Resources/OpenNook-NOTICE.md"
cp -R "$ROOT/Vendor/OpenNook/ThirdPartyLicenses" "$APP/Contents/Resources/"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
