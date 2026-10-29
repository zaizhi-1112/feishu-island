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
HELPERS = {'agent-status-helper', 'lark-cli', 'feishu-hub-helper'}
CHECKIN_FILES = set()
RESOURCE_FILES = {'deepseek-balance.cjs', 'AppIcon.icns', 'LarkCLI-LICENSE', 'OpenNook-LICENSE', 'NookSurface-LICENSE', 'OpenNook-NOTICE.md', '开始使用.html'}
RESOURCE_DIRS = {'ThirdPartyLicenses'}
WEB_FILES = {'avatar-virxact.svg', 'deepseek-icon.ico', 'avatar-virxact.png', 'pet-codex.png', 'style.css', 'codex-atlas.webp', 'virxact-logo.svg', 'agent-codex.png', 'pet-workbuddy.svg', 'avatar-workbuddy.png', 'agent-workbuddy.png', 'avatar-codex.png', 'pet-workbuddy.png', 'avatar-claude.png', 'todos.js', 'skin-v2.css', 'agent-claude.png', 'app.js', 'brand-flow.json', 'index.html', 'skin-effects.js', 'virxact-logo.png', 'brand-geometry.json', 'pet-codex.svg', 'pet-claude.png', 'skins.json', 'pet-claude.svg'}
# Native SkinManifest / SkinResources consume these assets directly. The three
# JSON files are required at startup; the images keep all four native themes
# complete. Legacy browser scripts are allowed source assets, not dependencies.
REQUIRED_SKIN_FILES = {'skins.json', 'brand-geometry.json', 'brand-flow.json',
                       'pet-codex.png', 'pet-claude.png', 'pet-workbuddy.png',
                       'avatar-codex.png', 'avatar-claude.png', 'avatar-workbuddy.png',
                       'avatar-virxact.png', 'virxact-logo.png', 'agent-codex.png', 'deepseek-icon.ico'}
EXTENSION_FILES = set()
LOL_FILES = {'THIRD_PARTY_NOTICES.md', 'push.png', 'pingwheel_enemyvisionrender.png', 'LICENSE.txt', 'omw.png', 'all_in.png', 'need_vision.png', 'enemy_missing.png', 'pingwheel_retreatrender.png', 'generic_ping.png', 'Base.wav', 'assist_me.png'}
REMINDER_FILES = {'cat-walk.mov', 'rick-portal.mov', 'what-a-day-alpha.mov', 'gemini-greeting-alpha.mov', 'SOURCE.txt'}
VOLUME_NAME = '一切在岛'
VOLUME_METADATA = {'.background', '.DS_Store', '.fseventsd', '.Trashes', '.TemporaryItems', '.VolumeIcon.icns'}
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
    source = LAYOUT_DIR/metadata['background']
    if source.is_symlink() or hashlib.sha256(source.read_bytes()).hexdigest() != metadata['backgroundSha256']:
        raise ValueError('Installer guide digest mismatch')
    (root/'.background').mkdir()
    (root/'.background'/metadata['background']).write_bytes(source.read_bytes())
    return metadata


SPARKLE_FILES = json.loads((Path(__file__).resolve().parents[1] / "Vendor/Sparkle/runtime-files.json").read_text())

def allowed(path):
    if path.as_posix() == "Contents/Resources/Sparkle-LICENSE":
        return True
    if path.parts[:3] == ("Contents", "Frameworks", "Sparkle.framework"):
        return "/".join(path.parts[3:]) in SPARKLE_FILES

    parts = path.parts
    name = path.as_posix()
    if any(p.startswith('.') for p in parts):
        return False
    if name in CHECKIN_FILES:
        return True
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
    if len(parts) == 4 and parts[2] == 'LOLPing':
        return parts[3] in LOL_FILES
    if len(parts) == 4 and parts[2] == 'ScreenReminder':
        return parts[3] in REMINDER_FILES
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
        framework = relative.parts[:3] == ('Contents', 'Frameworks', 'Sparkle.framework')
        expected = SPARKLE_FILES.get('/'.join(relative.parts[3:])) if framework else None
        if item.is_symlink():
            if not expected or expected.get('link') != str(item.readlink()) or not item.resolve().is_relative_to((app/'Contents/Frameworks/Sparkle.framework').resolve()):
                raise ValueError('Unexpected application symlinks')
            entries.append({'path': relative.as_posix(), 'symlink': str(item.readlink())})
            continue
        if framework and item.is_file() and (not expected or expected.get('sha256') != hashlib.sha256(item.read_bytes()).hexdigest()):
            raise ValueError('Sparkle framework differs from the pinned official runtime')
        if item.is_dir():
            continue
        if not item.is_file() or not allowed(relative):
            raise ValueError('Unexpected application file; distribution stopped: ' + relative.as_posix())
        entries.append({'path': relative.as_posix(), 'sha256': hashlib.sha256(item.read_bytes()).hexdigest()})
    required = {'Contents/Info.plist', 'Contents/MacOS/YuIsland', 'Contents/Resources/AppIcon.icns'} | {'Contents/Helpers/' + x for x in HELPERS}
    required |= CHECKIN_FILES
    required |= {'Contents/Resources/BrowserBridge/chrome-reader/' + x for x in EXTENSION_FILES}
    required |= {'Contents/Resources/ScreenReminder/' + x for x in REMINDER_FILES}
    required |= {'Contents/Resources/LOLPing/' + x for x in LOL_FILES}
    required |= {'Contents/Resources/SettingsWeb/' + x for x in REQUIRED_SKIN_FILES}
    required.add('Contents/Resources/开始使用.html')
    required.add('Contents/Resources/deepseek-balance.cjs')
    if not required.issubset({e['path'] for e in entries}):
        raise ValueError('Required runtime helpers or resources are missing')
    with (app / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if info.get('SUFeedURL'):
        expected_paths = {'Contents/Frameworks/Sparkle.framework/' + x for x in SPARKLE_FILES}
        if not expected_paths.issubset({e['path'] for e in entries}):
            raise ValueError('Sparkle runtime is incomplete')
        if info.get('SUFeedURL') != 'https://github.com/zaizhi-1112/feishu-island/releases/latest/download/appcast.xml' or info.get('SUPublicEDKey') != 'Ie5jh8XLKtdMSEBPc3rgUcxuIaj0EJouUgfKe0n47AM=':
            raise ValueError('Update feed or public signing key differs from the release contract')
    if info.get('CFBundleIdentifier') != 'local.zaizhi.feishu-island.preview':
        raise ValueError('Unexpected application identity')
    return info, entries


def verify_runtime(app):
    """Read-only verification; preserve the app and every helper's signing bytes."""
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    architectures = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/YuIsland')], text=True).split())
    for name in sorted(HELPERS):
        subprocess.run(['codesign', '--verify', '--strict', str(app/'Contents/Helpers'/name)], check=True, capture_output=True)
        helper_archs = set(subprocess.check_output(['lipo', '-archs', str(app/'Contents/Helpers'/name)], text=True).split())
        if not architectures.issubset(helper_archs):
            raise ValueError('Helper architecture mismatch: ' + name)
    if not architectures or not architectures.issubset({'arm64', 'x86_64'}):
        raise ValueError('Unsupported architecture')
    return sorted(architectures)


def inspect_volume(root, app_name, expected_info, expected_entries, expected_layout=None):
    visible = {p.name for p in root.iterdir() if not p.name.startswith('.')}
    if visible != {app_name, 'Applications'}:
        raise ValueError('DMG must show only the application and Applications shortcut')
    if any(p.name.startswith('.') and p.name not in VOLUME_METADATA for p in root.iterdir()):
        raise ValueError('Unexpected hidden material in the DMG root')
    shortcut = root/'Applications'
    if not shortcut.is_symlink() or shortcut.readlink().as_posix() != '/Applications':
        raise ValueError('Invalid Applications shortcut')
    metadata = expected_layout or layout_template(app_name)[0]
    stored_layout = root/'.DS_Store'
    if stored_layout.is_symlink() or not stored_layout.is_file() or hashlib.sha256(stored_layout.read_bytes()).hexdigest() != metadata['sha256']:
        raise ValueError('DMG Finder icon layout is missing or changed')
    background = root/'.background'
    if background.is_symlink() or not background.is_dir() or {p.name for p in background.iterdir()} != {metadata['background']}:
        raise ValueError('Installer guide must contain only the reviewed illustration')
    guide = background/metadata['background']
    if guide.is_symlink() or not guide.is_file() or hashlib.sha256(guide.read_bytes()).hexdigest() != metadata['backgroundSha256']:
        raise ValueError('Installer guide is missing or changed')
    copied_info, copied_entries = inspect(root/app_name)
    if copied_info != expected_info or copied_entries != expected_entries:
        raise ValueError('Application changed during packaging; retained for inspection, not released')


def verify_dmg(archive, mountpoint, app_name, info, entries, architectures, layout=None):
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
        if not any(item.get('mount-point') and Path(item['mount-point']).samefile(mountpoint) for item in entities):
            raise ValueError('DMG did not mount at its isolated verification path')
        inspect_volume(mountpoint, app_name, info, entries, layout)
        if verify_runtime(mountpoint/app_name) != architectures:
            raise ValueError('Mounted application architecture changed')
    finally:
        subprocess.run(['hdiutil', 'detach', str(mountpoint)], check=True, capture_output=True)


def package(app, output):
    app = app.resolve()
    output = output.resolve()
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
    # Finder aliases must identify the actual image's volume and file IDs. A
    # synthetic path-only alias can silently show a blank installation window.
    from ds_store import DSStore
    from mac_alias import Alias
    working = stage/'working-image.dmg'
    volume_name = VOLUME_NAME + ' ' + version
    subprocess.run(['hdiutil', 'create', '-volname', volume_name, '-srcfolder', str(image_root),
                    '-fs', 'HFS+', '-format', 'UDRW', str(working)],
                   check=True, capture_output=True)
    mount = stage/'layout-mount'; mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-noautoopen', '-mountpoint', str(mount), str(working)], check=True, capture_output=True)
    try:
        alias = Alias.for_file(str(mount/'.background'/layout['background']))
        # Do not embed the build machine's directory in the distributed alias.
        alias.volume.posix_path = '/Volumes/' + volume_name
        with DSStore.open(str(mount/'.DS_Store'), 'r+') as store:
            options = store['.']['icvp']; options['backgroundImageAlias'] = alias.to_bytes()
            store['.']['icvp'] = options
        layout = dict(layout, sha256=hashlib.sha256((mount/'.DS_Store').read_bytes()).hexdigest(), volumeName=volume_name)
        inspect_volume(mount, app.name, info, entries, layout)
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, capture_output=True)
    subprocess.run(['hdiutil', 'convert', str(working), '-format', 'UDZO', '-o', str(archive)], check=True, capture_output=True)
    verify_dmg(archive, stage/'verification-mount', app.name, info, entries, architectures, layout)
    # Recheck the source without modifying it; a concurrent rebuild is not a valid release.
    if inspect(app) != (info, entries):
        raise ValueError('Source application changed while packaging')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                'architectures': architectures, 'minimumMacOS': info['LSMinimumSystemVersion'],
                'status': 'pilot-preparation', 'colleagueAccountVerified': False,
                'notarized': False, 'includesPersonalCredentials': False,
                'format': 'dmg', 'archive': archive.name, 'sha256': digest,
                'installation': 'drag-to-applications', 'browserExtensionEmbedded': False,
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
