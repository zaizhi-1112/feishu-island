#!/usr/bin/env python3
"""Create an uninstalled pilot kit. Never copies profiles, home folders or credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPERS = {'lark-cli', 'feishu-hub-helper', 'feishu-dot-auth', 'feishu-tunnel-auth', 'tunnel-client'}
RESOURCE_FILES = {'AppIcon.icns', 'LarkCLI-LICENSE', 'OpenNook-LICENSE', 'NookSurface-LICENSE', 'OpenNook-NOTICE.md'}
RESOURCE_DIRS = {'ThirdPartyLicenses', 'TunnelClientLicenses'}
WEB_FILES = {'index.html', 'app.js', 'style.css'}
EXTENSION_FILES = {'manifest.json', 'popup.html', 'popup.css', 'popup.js', 'extract.js'}


def allowed(path):
    parts = path.parts
    name = path.as_posix()
    if any(p.startswith('.') for p in parts):
        return False
    if name in {'Contents/Info.plist', 'Contents/MacOS/YuIsland', 'Contents/_CodeSignature/CodeResources'}:
        return True
    if len(parts) == 3 and parts[:2] == ('Contents', 'Helpers'):
        return parts[2] in HELPERS
    if parts[:2] != ('Contents', 'Resources'):
        return False
    if len(parts) == 3:
        return parts[2] in RESOURCE_FILES
    if len(parts) == 4 and parts[2] == 'SettingsWeb':
        return parts[3] in WEB_FILES
    if name == 'Contents/Resources/BrowserBridge/doubao-work.js':
        return True
    if len(parts) == 5 and parts[2:4] == ('BrowserBridge', 'chrome-reader'):
        return parts[4] in EXTENSION_FILES
    if parts[2] in RESOURCE_DIRS:
        return path.suffix.lower() in {'.txt', '.md', ''} and not any(x.lower() in {'config', 'credentials', 'auth', 'workspace'} for x in parts)
    return False


def inspect(app):
    if app.is_symlink() or not app.is_dir():
        raise ValueError('Expected an actual application directory')
    entries = []
    for item in sorted(app.rglob('*')):
        relative = item.relative_to(app)
        if item.is_symlink():
            raise ValueError('Application symlinks are not permitted')
        if item.is_dir():
            continue
        if not item.is_file() or not allowed(relative):
            raise ValueError('Unexpected application file; distribution stopped: ' + relative.as_posix())
        entries.append({'path': relative.as_posix(), 'sha256': hashlib.sha256(item.read_bytes()).hexdigest()})
    required = {'Contents/Info.plist', 'Contents/MacOS/YuIsland'} | {'Contents/Helpers/' + x for x in HELPERS}
    required |= {'Contents/Resources/BrowserBridge/chrome-reader/' + x for x in EXTENSION_FILES}
    if not required.issubset({e['path'] for e in entries}):
        raise ValueError('Required runtime helpers or browser extension are missing')
    with (app / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if info.get('CFBundleIdentifier') != 'local.zaizhi.feishu-island.preview':
        raise ValueError('Unexpected application identity')
    return info, entries


def package(app, output):
    app = app.absolute()
    info, entries = inspect(app)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
    architectures = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/YuIsland')], text=True).split())
    for name in HELPERS:
        helper_archs = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/Helpers'/name)], text=True).split())
        if not architectures.issubset(helper_archs):
            raise ValueError('Helper architecture mismatch: ' + name)
    if not architectures or not architectures.issubset({'arm64', 'x86_64'}):
        raise ValueError('Unsupported architecture')
    output.mkdir(parents=True, exist_ok=True)
    # A new directory per invocation; never replaces a prior kit or installation.
    stage = Path(tempfile.mkdtemp(prefix='pilot-', dir=output))
    kit = stage/'飞书工作岛试用包'
    kit.mkdir()
    subprocess.run(['ditto', '--norsrc', '--noextattr', str(app), str(kit/app.name)], check=True)
    copied_info, copied_entries = inspect(kit/app.name)
    if copied_info != info or copied_entries != entries:
        raise ValueError('Application changed during packaging; retained for inspection, not released')
    shutil.copytree(ROOT/'BrowserBridge/chrome-reader', kit/'飞书工作岛网页收录', ignore=lambda d, names: [n for n in names if n not in EXTENSION_FILES])
    shutil.copyfile(ROOT/'Distribution/开始使用.html', kit/'开始使用.html')
    manifest = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                'architectures': sorted(architectures), 'minimumMacOS': info['LSMinimumSystemVersion'],
                'status': 'pilot-preparation', 'colleagueAccountVerified': False,
                'notarized': False, 'includesPersonalCredentials': False, 'files': entries}
    (kit/'package-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    archive = stage/'飞书工作岛试用包.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(kit), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (stage/'SHA256SUMS').write_text(digest+'  '+archive.name+'\n')
    print(json.dumps({'archive': str(archive), 'sha256': digest, 'architectures': sorted(architectures),
                      'status': 'pilot-preparation'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'releases')
    args = parser.parse_args()
    package(args.app, args.output)
