#!/usr/bin/env python3
"""Stage only download-page assets and an audited pilot ZIP for virxact deploy_app."""
from pathlib import Path
import argparse, hashlib, json, shutil, zipfile
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('package', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
with zipfile.ZipFile(a.package) as z:
    if z.testzip() is not None:
        raise SystemExit('Invalid package CRC')
    # ditto can encode the enclosing Chinese directory using legacy ZIP flags.
    manifests = [n for n in z.namelist() if n.count('/') == 1 and n.endswith('/package-manifest.json')]
    if len(manifests) != 1: raise SystemExit('Expected exactly one package manifest')
    manifest = json.loads(z.read(manifests[0]))
    if (manifest['version'],manifest['build'],manifest['architectures'],manifest['status']) != ('0.7.0','29',['arm64'],'pilot-preparation'):
        raise SystemExit('Update page version and package rules before publishing a different release')
a.output.mkdir(parents=True,exist_ok=False)
for asset in (ROOT/'Distribution/site').iterdir():
    if asset.is_symlink(): raise SystemExit('Unexpected asset symlink')
    if asset.is_dir(): shutil.copytree(asset,a.output/asset.name)
    else: shutil.copyfile(asset,a.output/asset.name)
shutil.copyfile(ROOT/'Distribution/开始使用.html',a.output/'start.html')
name = 'feishu-island-0.7.0-build29-arm64-pilot.zip'
shutil.copyfile(a.package,a.output/name)
(a.output/'SHA256SUMS').write_text(hashlib.sha256(a.package.read_bytes()).hexdigest()+'  '+name+'\n')
print(a.output)
