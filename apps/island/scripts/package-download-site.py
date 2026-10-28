#!/usr/bin/env python3
"""Stage the existing authorization service and an audited Mac download, without secrets."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = {'index.html', 'install.js', 'install.css', 'landing.css', 'agent-guide.html',
          'icon.png', 'mascot.png', 'virxact-ui.css', 'virxact-story.css', 'vx.js'}
MAX_DMG_BYTES = 48_000_000  # Reserve room within the backend's 50 MB upload limit.
SERVICE = {'server.cjs', 'core.cjs', 'desktop.cjs', 'package.json', 'package-lock.json', 'virxact.json'}


def validate(package, manifest, root=ROOT):
    if package.is_symlink() or not package.is_file() or package.suffix != '.dmg':
        raise ValueError('Expected an audited DMG file')
    if package.stat().st_size > MAX_DMG_BYTES:
        raise ValueError('DMG exceeds the download service upload budget; compress media before publishing')
    info = plistlib.loads((root/'Resources/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    expected = (version, build, ['arm64'], 'pilot-preparation', 'dmg')
    if tuple(manifest.get(k) for k in ['version', 'build', 'architectures', 'status', 'format']) != expected:
        raise ValueError('Source and package release metadata differ')
    name = f'feishu-island-{version}-build{build}-arm64.dmg'
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if package.name != name or manifest.get('archive') != name or manifest.get('sha256') != digest:
        raise ValueError('DMG does not match its audit manifest')
    if manifest.get('includesPersonalCredentials') is not False or manifest.get('browserExtensionEmbedded') is not False:
        raise ValueError('Unexpected distribution boundary')
    checks = ['imageIntegrity', 'readOnlyMounted', 'bundleHashesMatch', 'signatureValid', 'detached']
    if any(manifest.get('verification', {}).get(k) is not True for k in checks):
        raise ValueError('Incomplete DMG verification')
    page = (root/'Distribution/site/index.html').read_text()
    if name not in page or f'content="{version}/{build}/arm64"' not in page:
        raise ValueError('Page and package release metadata differ')
    guide = root/'Distribution/开始使用.html'
    if f'{version} · build{build}' not in guide.read_text():
        raise ValueError('Installation guide and package build differ')
    bundled = next((f['sha256'] for f in manifest['files'] if f['path'] == 'Contents/Resources/开始使用.html'), None)
    if bundled != hashlib.sha256(guide.read_bytes()).hexdigest():
        raise ValueError('Hosted and bundled installation guides differ')
    previous = json.loads((root/'Distribution/released-packages.json').read_text())
    if not all(isinstance(x, str) and re.fullmatch(r'feishu-island-[0-9.]+-build[0-9]+-arm64\.dmg', x) for x in previous):
        raise ValueError('Unexpected legacy download path')
    return name, digest, {old: name for old in previous if old != name}


def copy_regular(source, destination):
    if source.is_symlink() or not source.is_file():
        raise ValueError('Expected a regular release asset: ' + source.name)
    shutil.copyfile(source, destination)


def web_guide(source):
    """Keep the offline guide's content while honoring the service's self-only CSP."""
    styles = re.findall(r'<style>(.*?)</style>', source, re.S)
    if len(styles) != 1:
        raise ValueError('Expected one self-contained guide stylesheet')
    html = re.sub(r'<style>.*?</style>', '<link rel="stylesheet" href="start.css">', source, flags=re.S)
    for size in ('21px', '23px'):
        html = html.replace(f'onclick="document.body.style.fontSize=\'{size}\'"', f'data-reading-size="{size}"')
    html = html.replace('style="width:100%;height:auto;border-radius:16px"', 'class="install-illustration"')
    if re.search(r'\s(?:on\w+|style)\s*=', html, re.I):
        raise ValueError('Guide still contains inline behavior forbidden by CSP')
    html = html.replace('</head>', '<script src="start.js" defer></script></head>')
    css = styles[0] + '\n.install-illustration{width:100%;height:auto;border-radius:16px}\n'
    js = "document.querySelectorAll('[data-reading-size]').forEach(button=>button.addEventListener('click',()=>{document.body.style.fontSize=button.dataset.readingSize;}));\n"
    return html, css, js


def stage(package, output, manifest_path=None):
    manifest = json.loads((manifest_path or package.parent/'package-manifest.json').read_text())
    name, digest, aliases = validate(package, manifest)
    output.mkdir(parents=True, exist_ok=False)
    public = output/'public'; public.mkdir()
    for asset in sorted(SERVICE):
        copy_regular(ROOT/'AuthService'/asset, output/asset)
    for asset in sorted(PUBLIC):
        copy_regular(ROOT/'Distribution/site'/asset, public/asset)
    for asset in ('connect.html', 'connect.js'):
        copy_regular(ROOT/'AuthService/public'/asset, public/asset)
    html, css, js = web_guide((ROOT/'Distribution/开始使用.html').read_text())
    for filename, text in [('start.html', html), ('start.css', css), ('start.js', js)]:
        (public/filename).write_text(text)
    copy_regular(package, public/name)
    (public/'download-aliases.json').write_text(json.dumps(aliases, indent=2)+'\n')
    (public/'SHA256SUMS').write_text(digest+'  '+name+'\n')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    print(stage(args.package, args.output, args.manifest))
