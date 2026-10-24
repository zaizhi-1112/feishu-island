#!/usr/bin/env python3
"""Stage the authorized service and existing audited download without private files."""
from pathlib import Path
import argparse, re, shutil
p=argparse.ArgumentParser();p.add_argument('download',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
if not (a.download/'index.html').is_file() or not (a.download/'SHA256SUMS').is_file(): raise SystemExit('Audited download staging required')
a.output.mkdir(parents=True,exist_ok=False)
for name in ['server.cjs','core.cjs','desktop.cjs','package.json','package-lock.json','virxact.json']: shutil.copyfile(root/'AuthService'/name,a.output/name)
shutil.copytree(a.download,a.output/'public')
for file in (root/'AuthService/public').iterdir():
 if file.is_symlink() or not file.is_file() or file.suffix not in {'.html','.js','.css','.png'}: raise SystemExit('Unexpected service asset')
 shutil.copyfile(file,a.output/'public'/file.name)
# The offline source stays self-contained. Its hosted copy must obey the
# service's existing style-src 'self' policy without allowing inline styles.
start=a.output/'public/start.html'
if not start.is_file(): raise SystemExit('Hosted start.html is required')
html=start.read_text()
styles=re.findall(r'<style>(.*?)</style>',html,flags=re.I|re.S)
if len(styles)!=1 or len(re.findall(r'<style\b',html,flags=re.I))!=1:
 raise SystemExit('Expected one plain inline style block in hosted start.html')
(a.output/'public/start.css').write_text(styles[0]+'\n')
start.write_text(re.sub(r'<style>.*?</style>','<link rel="stylesheet" href="start.css">',html,count=1,flags=re.I|re.S))
print(a.output)
