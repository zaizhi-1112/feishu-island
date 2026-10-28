#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ISLAND_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
SCRATCH="$ROOT/.build/dot-release"
APP="$ROOT/.build/dot-sandbox/你的飞包联调.app"
if pgrep -f "^$APP/Contents/MacOS/YuIsland$" >/dev/null; then
    echo '独立联调窗口正在运行，保留原程序；请先关闭联调窗口再重新构建。' >&2
    exit 1
fi
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -j 2 --sdk "$SDK" -c release --product YuIsland
BIN_DIR="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" --sdk "$SDK" -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/YuIsland" "$APP/Contents/MacOS/YuIsland"
python3 - "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
p['CFBundleIdentifier']='local.zaizhi.feishu-island.dot-sandbox'
p['CFBundleDisplayName']='你的飞包联调'
p['CFBundleName']='你的飞包联调'
p['LSUIElement']=False
with open(sys.argv[2],'wb') as f: plistlib.dump(p,f)
PY
ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-dot-auth-helper.sh"
mkdir -p "$APP/Contents/Helpers"
cp "$ROOT/.build/dot-auth-helper/feishu-dot-auth" "$APP/Contents/Helpers/feishu-dot-auth"
if [[ -x "$ROOT/.build/tunnel-client/unpacked/tunnel-client" ]]; then
    [[ "$(shasum -a 256 "$ROOT/.build/tunnel-client/unpacked/tunnel-client" | cut -d ' ' -f 1)" == 'd8f165d8175fa9f813a113b6ef434aed25a384f765a69b3709228704e5347474' ]] || { echo 'Tunnel client checksum mismatch' >&2; exit 1; }
    ISLAND_SDK="$SDK" bash "$ROOT/scripts/build-tunnel-helper.sh"
    cp "$ROOT/.build/tunnel-auth-helper/feishu-tunnel-auth" "$APP/Contents/Helpers/feishu-tunnel-auth"
    cp "$ROOT/.build/tunnel-client/unpacked/tunnel-client" "$APP/Contents/Helpers/tunnel-client"
    mkdir -p "$APP/Contents/Resources/TunnelClientLicenses"
    cp "$ROOT/.build/tunnel-client/unpacked/LICENSE" "$ROOT/.build/tunnel-client/unpacked/NOTICE" "$ROOT/.build/tunnel-client/unpacked/"*-licenses.txt "$APP/Contents/Resources/TunnelClientLicenses/"
fi
# Only an ordinary synthetic window. No account CLI, Hub helper, login item or overlay assets.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built isolated sandbox: %s\n' "$APP"
