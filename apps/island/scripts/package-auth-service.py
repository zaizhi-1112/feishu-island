#!/usr/bin/env python3
"""Stage the authorized service and existing audited download without private files."""
from pathlib import Path
import argparse, shutil
p=argparse.ArgumentParser();p.add_argument('download',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
if not (a.download/'index.html').is_file() or not (a.download/'SHA256SUMS').is_file(): raise SystemExit('Audited download staging required')
a.output.mkdir(parents=True,exist_ok=False)
for name in ['server.cjs','core.cjs','desktop.cjs','package.json','package-lock.json','virxact.json']: shutil.copyfile(root/'AuthService'/name,a.output/name)
shutil.copytree(a.download,a.output/'public')
for file in (root/'AuthService/public').iterdir():
 if file.is_symlink() or not file.is_file() or file.suffix not in {'.html','.js','.css','.png'}: raise SystemExit('Unexpected service asset')
 shutil.copyfile(file,a.output/'public'/file.name)
p=a.output/'public/index.html';s=p.read_text();s=s.replace('安装后的无命令行授权引导、每人的 Dot 配对与自动通知，以及史天佑本人设备的完整验收。','Mac 与公司授权的自动接续、每人的 Dot 配对与自动通知，以及史天佑本人设备的完整验收。');s=s.replace('<a href="start.html">','<a class="vx-btn" href="connect.html">连接自己的飞书</a><a href="start.html">');p.write_text(s)
print(a.output)
