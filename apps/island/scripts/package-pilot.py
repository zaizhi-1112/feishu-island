#!/usr/bin/env python3
"""Create a drag-to-Applications DMG without installing or starting the application.

Only the audited app and Applications shortcut are visible on the volume. The audit
manifest stays beside the DMG, never inside the user's installation window.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPERS = {'lark-cli', 'feishu-hub-helper', 'feishu-dot-auth', 'feishu-tunnel-auth', 'tunnel-client'}
RESOURCE_FILES = {'AppIcon.icns', 'LarkCLI-LICENSE', 'OpenNook-LICENSE', 'NookSurface-LICENSE', 'OpenNook-NOTICE.md'}
RESOURCE_DIRS = {'ThirdPartyLicenses', 'TunnelClientLicenses'}
WEB_FILES = {'avatar-virxact.png', 'pet-codex.png', 'style.css', 'codex-atlas.webp', 'virxact-logo.svg', 'agent-codex.png', 'pet-workbuddy.svg', 'avatar-workbuddy.png', 'agent-workbuddy.png', 'avatar-codex.png', 'pet-workbuddy.png', 'avatar-claude.png', 'todos.js', 'skin-v2.css', 'agent-claude.png', 'app.js', 'brand-flow.json', 'index.html', 'skin-effects.js', 'virxact-logo.png', 'brand-geometry.json', 'pet-codex.svg', 'pet-claude.png', 'skins.json', 'pet-claude.svg'}
EXTENSION_FILES = {'manifest.json', 'popup.html', 'popup.css', 'popup.js', 'extract.js'}
REMINDER_FILES = {'rick-portal.mov', 'SOURCE.txt'}
VOLUME_NAME = '飞书工作岛'
VOLUME_METADATA = {'.DS_Store', '.fseventsd', '.Trashes', '.TemporaryItems', '.VolumeIcon.icns'}
LAYOUT_DIR = ROOT/'scripts/dmg-layout'


def layout_template(app_name):
    metadata = json.loads((LAYOUT_DIR/'layout.json').read_text())
    if metadata.get('appName') != app_name:
        raise ValueError('Application name does not match the reviewed Finder layout')
    template = LAYOUT_DIR/'FinderLayout.dsstore'
    if template.is_symlink() or not template.is_file():
        raise ValueError('Finder layout template must be a regular file')
    data = template.read_bytes()
    if hashlib.sha256(data).hexdigest() != metadata.get('sha256'):
        raise ValueError('Finder layout template digest mismatch')
    return metadata, data


def install_layout(root, app_name):
    metadata, data = layout_template(app_name)
    with (root/'.DS_Store').open('xb') as file:
        file.write(data)
    return metadata


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
    if len(parts) == 4 and parts[2] == 'ScreenReminder':
        return parts[3] in REMINDER_FILES
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
    required = {'Contents/Info.plist', 'Contents/MacOS/YuIsland', 'Contents/Resources/AppIcon.icns'} | {'Contents/Helpers/' + x for x in HELPERS}
    required |= {'Contents/Resources/BrowserBridge/chrome-reader/' + x for x in EXTENSION_FILES}
    required |= {'Contents/Resources/ScreenReminder/' + x for x in REMINDER_FILES}
    if not required.issubset({e['path'] for e in entries}):
        raise ValueError('Required runtime helpers or browser extension are missing')
    with (app / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if info.get('CFBundleIdentifier') != 'local.zaizhi.feishu-island.preview':
        raise ValueError('Unexpected application identity')
    return info, entries


def verify_runtime(app):
    """Read-only verification; preserve the app and every helper's signing bytes."""
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
    architectures = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/YuIsland')], text=True).split())
    for name in HELPERS:
        helper_archs = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/Helpers'/name)], text=True).split())
        if not architectures.issubset(helper_archs):
            raise ValueError('Helper architecture mismatch: ' + name)
    if not architectures or not architectures.issubset({'arm64', 'x86_64'}):
        raise ValueError('Unsupported architecture')
    return sorted(architectures)


def inspect_volume(root, app_name, expected_info, expected_entries):
    visible = {p.name for p in root.iterdir() if not p.name.startswith('.')}
    if visible != {app_name, 'Applications'}:
        raise ValueError('DMG must show only the application and Applications shortcut')
    if any(p.name.startswith('.') and p.name not in VOLUME_METADATA for p in root.iterdir()):
        raise ValueError('Unexpected hidden material in the DMG root')
    shortcut = root/'Applications'
    if not shortcut.is_symlink() or shortcut.readlink().as_posix() != '/Applications':
        raise ValueError('Invalid Applications shortcut')
    metadata, _ = layout_template(app_name)
    stored_layout = root/'.DS_Store'
    if stored_layout.is_symlink() or not stored_layout.is_file() or hashlib.sha256(stored_layout.read_bytes()).hexdigest() != metadata['sha256']:
        raise ValueError('DMG Finder icon layout is missing or changed')
    copied_info, copied_entries = inspect(root/app_name)
    if copied_info != expected_info or copied_entries != expected_entries:
        raise ValueError('Application changed during packaging; retained for inspection, not released')


def verify_dmg(archive, mountpoint, app_name, info, entries, architectures):
    subprocess.run(['hdiutil', 'verify', str(archive)], check=True, capture_output=True)
    mountpoint.mkdir()
    attached = subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                               '-mountpoint', str(mountpoint), '-plist', str(archive)],
                              check=True, capture_output=True)
    # The mountpoint was newly created for this invocation. Always detach this exact mount,
    # including malformed plist/failed audit paths; never unmount unrelated user volumes.
    try:
        details = plistlib.loads(attached.stdout)
        entities = details.get('system-entities', [])
        if not any(item.get('mount-point') == str(mountpoint) for item in entities):
            raise ValueError('DMG did not mount at its isolated verification path')
        inspect_volume(mountpoint, app_name, info, entries)
        if verify_runtime(mountpoint/app_name) != architectures:
            raise ValueError('Mounted application architecture changed')
    finally:
        subprocess.run(['hdiutil', 'detach', str(mountpoint)], check=True, capture_output=True)


def package(app, output):
    app = app.absolute()
    output = output.absolute()
    info, entries = inspect(app)
    architectures = verify_runtime(app)
    version, build = info.get('CFBundleShortVersionString', ''), info.get('CFBundleVersion', '')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', str(version)) or not re.fullmatch(r'[0-9]+', str(build)):
        raise ValueError('Invalid release version or build number')
    output.mkdir(parents=True, exist_ok=True)
    # A new directory per invocation; never replaces a prior artifact or installation.
    stage = Path(tempfile.mkdtemp(prefix='pilot-', dir=output))
    image_root = stage/'image-root'
    image_root.mkdir()
    subprocess.run(['ditto', '--norsrc', '--noextattr', str(app), str(image_root/app.name)], check=True)
    (image_root/'Applications').symlink_to('/Applications', target_is_directory=True)
    layout = install_layout(image_root, app.name)
    inspect_volume(image_root, app.name, info, entries)
    verify_runtime(image_root/app.name)
    archive = stage/f'feishu-island-{version}-build{build}-{"-".join(architectures)}.dmg'
    subprocess.run(['hdiutil', 'create', '-volname', VOLUME_NAME, '-srcfolder', str(image_root),
                    '-fs', 'HFS+', '-format', 'UDZO', str(archive)],
                   check=True, capture_output=True)
    verify_dmg(archive, stage/'verification-mount', app.name, info, entries, architectures)
    # Recheck the source without modifying it; a concurrent rebuild is not a valid release.
    if inspect(app) != (info, entries):
        raise ValueError('Source application changed while packaging')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                'architectures': architectures, 'minimumMacOS': info['LSMinimumSystemVersion'],
                'status': 'pilot-preparation', 'colleagueAccountVerified': False,
                'notarized': False, 'includesPersonalCredentials': False,
                'format': 'dmg', 'archive': archive.name, 'sha256': digest,
                'installation': 'drag-to-applications', 'browserExtensionEmbedded': True,
                'finderLayout': layout,
                'verification': {'imageIntegrity': True, 'readOnlyMounted': True,
                                 'bundleHashesMatch': True, 'signatureValid': True, 'detached': True},
                'files': entries}
    manifest_path = stage/'package-manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    (stage/'SHA256SUMS').write_text(digest+'  '+archive.name+'\n')
    print(json.dumps({'archive': str(archive), 'manifest': str(manifest_path), 'sha256': digest, 'architectures': architectures,
                      'status': 'pilot-preparation'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'releases')
    args = parser.parse_args()
    package(args.app, args.output)
