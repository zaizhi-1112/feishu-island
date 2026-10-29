#!/usr/bin/env python3
"""Prepare a signed Sparkle feed; publish only with explicit --publish.

Uses the project's existing GitHub identity and the local Sparkle signing key.
No private key export, token file, app data, or source archive is included.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REPO = 'zaizhi-1112/feishu-island'
KEY_ACCOUNT = 'feishu-island-release'


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def prepare(manifest, output):
    data = json.loads(manifest.read_text())
    # package-pilot's audited digest is required; never sign an arbitrary URL.
    dmg = manifest.parent / data['archive'] if not Path(data['archive']).is_absolute() else Path(data['archive'])
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    expected = data.get('sha256') or data.get('archiveSha256')
    if expected != digest:
        raise ValueError('Installer differs from the audited package manifest')
    version = str(data['version']); build = str(data['build'])
    tag = f'v{version}-build{build}'
    output.mkdir(parents=True, exist_ok=False)
    target = output / dmg.name
    shutil.copy2(dmg, target)
    (output / 'SHA256SUMS').write_text(digest + '  ' + dmg.name + '\n')
    shutil.copy2(manifest, output / 'manifest.json')
    shutil.copy2(ROOT / 'Distribution/开始使用.html', output / 'installation-guide.html')
    notes = '<p>安装盘恢复拖入应用程序的引导画面。新增收起时完全隐藏或露出黑边的选择；改善飞书授权后的连接状态和权限收窄。</p>'
    (output / (dmg.stem + '.html')).write_text(notes)
    tool = ROOT / '.build/artifacts/sparkle/Sparkle/bin/generate_appcast'
    run(str(tool), '--account', KEY_ACCOUNT, '--maximum-deltas', '0', '--download-url-prefix', f'https://github.com/{REPO}/releases/download/{tag}/', str(output))
    feed = output / 'appcast.xml'
    xml = feed.read_text()
    enclosure = ET.fromstring(xml).find('./channel/item/enclosure')
    if enclosure is None or not enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'):
        raise ValueError('Unsigned update archive')
    if '<!-- sparkle-signatures:' not in xml or '\nedSignature:' not in xml:
        raise ValueError('Signed feed was not generated')
    verifier = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
    run(str(verifier), '--account', KEY_ACCOUNT, '--verify', str(feed))
    run(str(verifier), '--account', KEY_ACCOUNT, '--verify', str(target), enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
    return {'tag': tag, 'version': version, 'build': build, 'sha256': digest, 'directory': str(output), 'files': [str(target), str(feed), str(output/'SHA256SUMS'), str(output/'manifest.json'), str(output/'installation-guide.html')]}


def publish(prepared):
    result = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True, check=True)
    if result.stdout.strip():
        raise ValueError('Commit and review source before publishing')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    tag = prepared['tag']
    directory = Path(prepared['directory']).resolve()
    manifest = json.loads((directory/'manifest.json').read_text())
    if tag != f"v{manifest['version']}-build{manifest['build']}":
        raise ValueError('Prepared tag differs from installer version')
    expected_names = {manifest['archive'], 'appcast.xml', 'SHA256SUMS', 'manifest.json', 'installation-guide.html'}
    files = [Path(f).resolve() for f in prepared['files']]
    if {f.name for f in files} != expected_names or any(f.parent != directory for f in files):
        raise ValueError('Only the reviewed release files may be uploaded')
    installer = directory/manifest['archive']
    if hashlib.sha256(installer.read_bytes()).hexdigest() != manifest['sha256']:
        raise ValueError('Prepared installer changed')
    run(str(ROOT/'.build/artifacts/sparkle/Sparkle/bin/sign_update'), '--account', KEY_ACCOUNT, '--verify', str(directory/'appcast.xml'))
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', REPO], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0:
        raise ValueError('Release exists; inspect its state before retrying to avoid duplicate publication')
    notes = Path(prepared['directory']) / 'release-notes.md'
    notes.write_text('安装盘恢复拖入应用程序的引导画面；收起时可选择完全隐藏或露出黑边。飞书连接增加权限收窄、连接进度和失败提示；复制后的启动避免重复进入安装器。\n\nApple 芯片 Mac，macOS 15+；安装包尚未 Apple 公证。两位同事报告的无法打开（其中一例 -47）尚未复现，安全提示后的完整首次启动和受影响同事的飞书连接仍需实机验证。build91 及更早版本请先手动安装一次。\n')
    run('gh', 'release', 'create', tag, '--repo', REPO, '--target', commit, '--draft', '--title', f"一切在岛 {prepared['version']} · build{prepared['build']}", '--notes-file', str(notes))
    run('gh', 'release', 'upload', tag, '--repo', REPO, *prepared['files'])
    run('gh', 'release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest')
    return f'https://github.com/{REPO}/releases/tag/{tag}'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--prepared', type=Path)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    if args.prepared:
        result = json.loads(args.prepared.read_text())
    else:
        if args.manifest is None or args.output is None:
            parser.error('--manifest and --output are required for preparation')
        result = prepare(args.manifest.resolve(), args.output.resolve())
        (args.output/'prepared.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    if args.publish:
        print(publish(result))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))
