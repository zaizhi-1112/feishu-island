#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
label=local.zaizhi.feishu-danmu-web
domain="gui/$(id -u)"
plist_path="$HOME/Library/LaunchAgents/$label.plist"
if [[ "${1:-}" == "--disable" ]]; then
  launchctl disable "$domain/$label"
  if launchctl print "$domain/$label" >/dev/null 2>&1; then launchctl bootout "$domain/$label"; fi
  echo '已停用飞书启动联动，保留文件以便恢复。'
  exit 0
fi
mkdir -p "$project_dir/.build" "$HOME/Library/Application Support/FeishuDanmuWeb" "$HOME/Library/LaunchAgents"
swiftc "$project_dir/Sources/Message.swift" "$project_dir/Sources/Overlay.swift" "$project_dir/scripts/AppearanceMCP.swift" "$project_dir/scripts/web-autostart.swift" -o "$project_dir/.build/feishu-danmu-web-autostart"
if [[ -f "$plist_path" ]]; then cp "$plist_path" "$project_dir/.build/autostart-previous-$(date +%Y%m%d-%H%M%S).plist"; fi
if [[ -f "$HOME/Library/Application Support/FeishuDanmuWeb/launcher" ]]; then cp "$HOME/Library/Application Support/FeishuDanmuWeb/launcher" "$project_dir/.build/desktop-component-previous-$(date +%Y%m%d-%H%M%S)"; fi
if launchctl print "$domain/$label" >/dev/null 2>&1; then launchctl bootout "$domain/$label"; fi
cp "$project_dir/.build/feishu-danmu-web-autostart" "$HOME/Library/Application Support/FeishuDanmuWeb/launcher"
python3 - <<'PY'
import pathlib,plistlib
home=pathlib.Path.home()
(home/'Library/LaunchAgents/local.zaizhi.feishu-danmu-web.plist').write_bytes(plistlib.dumps({'Label':'local.zaizhi.feishu-danmu-web','ProgramArguments':[str(home/'Library/Application Support/FeishuDanmuWeb/launcher')],'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background','ThrottleInterval':10}))
PY
plutil -lint "$plist_path"
launchctl enable "$domain/$label"
launchctl bootstrap "$domain" "$plist_path"
echo '已启用：飞书启动打开网页，网页连接本机透明桌面弹幕组件。'
