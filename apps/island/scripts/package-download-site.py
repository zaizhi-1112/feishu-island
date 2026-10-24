#!/usr/bin/env python3
"""Stage a verified DMG and the concise company installation page; no personal data."""
from pathlib import Path
import argparse, hashlib, json, shutil
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('package', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--manifest', type=Path)
a = p.parse_args()
manifest_path = a.manifest or a.package.parent/'package-manifest.json'
if a.package.is_symlink() or not a.package.is_file() or a.package.suffix != '.dmg':
    raise SystemExit('Expected an audited DMG file')
manifest = json.loads(manifest_path.read_text())
expected = ('0.7.0','30',['arm64'],'pilot-preparation','dmg')
if tuple(manifest.get(k) for k in ['version','build','architectures','status','format']) != expected:
    raise SystemExit('Update page version and package rules before publishing a different release')
name = 'feishu-island-0.7.0-build30-arm64.dmg'
digest = hashlib.sha256(a.package.read_bytes()).hexdigest()
if manifest.get('archive') != name or a.package.name != name or manifest.get('sha256') != digest:
    raise SystemExit('DMG does not match its audit manifest')
if manifest.get('includesPersonalCredentials') is not False or not manifest.get('browserExtensionEmbedded'):
    raise SystemExit('Unexpected distribution boundary')
checks = ['imageIntegrity','readOnlyMounted','bundleHashesMatch','signatureValid','detached']
if any(manifest.get('verification',{}).get(k) is not True for k in checks):
    raise SystemExit('Incomplete DMG verification')
page = (ROOT/'Distribution/site/index.html').read_text()
if name not in page or 'content="0.7.0/30/arm64"' not in page:
    raise SystemExit('Page and release metadata differ')
a.output.mkdir(parents=True,exist_ok=False)
for asset in (ROOT/'Distribution/site').iterdir():
    # The inherited design-kit favicon directory is unused; the user's icon is
    # the only icon linked by this page. Do not ship unreachable nested assets.
    if asset.name == 'brand' and asset.is_dir() and not asset.is_symlink():
        continue
    if asset.is_symlink() or not asset.is_file() or asset.suffix not in {'.html','.css','.js','.png','.svg'}:
        raise SystemExit('Unexpected public asset')
    shutil.copyfile(asset,a.output/asset.name)
shutil.copyfile(ROOT/'Distribution/开始使用.html',a.output/'start.html')
shutil.copyfile(a.package,a.output/name)
(a.output/'SHA256SUMS').write_text(digest+'  '+name+'\n')
print(a.output)
