#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${DANMU_APP_OUTPUT:-$PWD/飞书弹幕.app}"
# Do not replace the signed executable while an old process holds its TCC identity.
set +e
pgrep -x FeishuDanmu >/dev/null
process_status=$?
set -e
if [ "$process_status" -eq 0 ]; then
  if [ "${DANMU_STAGED_BUILD:-0}" != "1" ]; then
    echo '请先从菜单栏退出飞书弹幕，再构建。运行中覆盖应用会导致辅助功能授权与版本不一致。' >&2
    exit 1
  fi
  # Staging is allowed only in this project's .build tree. It never replaces
  # the active Desktop app and must not be launched until that app exits.
  python3 - "$APP" "$PWD/.build" <<'PY'
import pathlib,sys,subprocess
app,root=map(lambda x:pathlib.Path(x).resolve(),sys.argv[1:])
if not app.is_relative_to(root) or not app.name.startswith('staged-') or app.suffix!='.app':
    raise SystemExit('运行中只允许在本项目 .build/staged-*.app 制作待安装版本。')
target=(app/'Contents/MacOS/FeishuDanmu').resolve()
for pid in subprocess.check_output(['pgrep','-x','FeishuDanmu'],text=True).split():
    files=subprocess.run(['lsof','-a','-p',pid,'-d','txt','-Fn'],capture_output=True,text=True)
    if files.returncode != 0:
        raise SystemExit('无法确认运行中的可执行文件，停止暂存构建。')
    if any(pathlib.Path(line[1:]).resolve()==target for line in files.stdout.splitlines() if line.startswith('n')):
        raise SystemExit('该暂存应用仍在运行，不能覆盖。')
PY
elif [ "$process_status" -ne 1 ]; then
  echo '无法确认弹幕程序是否已退出，停止构建，避免覆盖运行中的应用。' >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" .build
cp 使用说明.html "$APP/Contents/Resources/使用说明.html"
cp Assets/dazai-dossier.png "$APP/Contents/Resources/dazai-dossier.png"
cp tools/lark-cli/bin/lark-cli "$APP/Contents/Helpers/lark-cli"
swiftc -module-cache-path "$PWD/.build" Sources/Message.swift Sources/ServerClock.swift Sources/AccountReader.swift Sources/Settings.swift Sources/Overlay.swift Sources/App.swift -o "$APP/Contents/MacOS/FeishuDanmu" -framework Cocoa -framework ApplicationServices
swift -module-cache-path "$PWD/.build" scripts/icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FeishuDanmu</string>
<key>CFBundleIdentifier</key><string>local.zaizhi.feishu-danmu</string>
<key>CFBundleName</key><string>飞书弹幕</string>
<key>CFBundleDisplayName</key><string>飞书弹幕</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.3.5</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
