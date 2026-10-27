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
expected = ('0.9.0','55',['arm64'],'pilot-preparation','dmg')
if tuple(manifest.get(k) for k in ['version','build','architectures','status','format']) != expected:
    raise SystemExit('Update page version and package rules before publishing a different release')
name = 'feishu-island-0.9.0-build55-arm64.dmg'
digest = hashlib.sha256(a.package.read_bytes()).hexdigest()
if manifest.get('archive') != name or a.package.name != name or manifest.get('sha256') != digest:
    raise SystemExit('DMG does not match its audit manifest')
if manifest.get('includesPersonalCredentials') is not False or manifest.get('browserExtensionEmbedded') is not False:
    raise SystemExit('Unexpected distribution boundary')
checks = ['imageIntegrity','readOnlyMounted','bundleHashesMatch','signatureValid','detached']
if any(manifest.get('verification',{}).get(k) is not True for k in checks):
    raise SystemExit('Incomplete DMG verification')
page = (ROOT/'Distribution/site/index.html').read_text()
if name not in page or 'content="0.9.0/55/arm64"' not in page:
    raise SystemExit('Page and release metadata differ')
# The hosted help and package must describe the same release.
help_source = ROOT/'Distribution/site/start-build55.html'  # Frozen with the hosted build55 package.
if 'build' + manifest['build'] not in help_source.read_text():
    raise SystemExit('Installation guide and package build differ; update them together before publishing')
a.output.mkdir(parents=True,exist_ok=False)
public = {'index.html','install.js','install.css','landing.css','agent-guide.html',
          'icon.png','mascot.png','virxact-ui.css','virxact-story.css','vx.js'}
for name_in_site in sorted(public):
    asset = ROOT/'Distribution/site'/name_in_site
    if asset.is_symlink() or not asset.is_file() or asset.suffix not in {'.html','.css','.js','.png','.svg'}:
        raise SystemExit('Unexpected public asset')
    shutil.copyfile(asset,a.output/asset.name)
shutil.copyfile(help_source,a.output/'start.html')
shutil.copyfile(a.package,a.output/name)
(a.output/'SHA256SUMS').write_text(digest+'  '+name+'\n')
print(a.output)
