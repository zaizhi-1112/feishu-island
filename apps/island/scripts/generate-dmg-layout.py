#!/usr/bin/env python3
"""Generate the reviewed Finder layout template, without driving Finder or mounting a disk.

Regeneration and packaging use ds_store==1.3.1 and mac_alias==2.2.2. Packaging
validates this template and binds its background alias to the actual disk. To change the layout,
write into a new --output directory, inspect it, then update both template and metadata.
Field meanings follow the upstream ds_store/dmgbuild implementations:
https://ds-store.readthedocs.io/en/latest/
https://github.com/dmgbuild/dmgbuild/blob/main/src/dmgbuild/core.py
https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
"""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from mac_alias import Alias, VolumeInfo, TargetInfo
from pathlib import Path
from ds_store import DSStore

APP_NAME = '一切在岛.app'
BOUNDS = '{{160, 100}, {820, 674}}'
POSITIONS = {APP_NAME: (230, 148), 'Applications': (590, 148)}


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    target = output/'FinderLayout.dsstore'
    metadata = output/'layout.json'
    if target.exists() or metadata.exists():
        raise ValueError('Choose a fresh output directory; preserve previous layout templates')
    date = datetime(2026, 1, 1, tzinfo=timezone.utc)
    background = Alias(volume=VolumeInfo('一切在岛', date, b'H+', 5, 0, b'\x00\x00', posix_path='/Volumes/一切在岛'),
        target=TargetInfo(0, 'background.tiff', 0xFFFFFFFF, 0xFFFFFFFF, date, b'\x00'*4, b'\x00'*4,
            folder_name='.background', posix_path='/.background/background.tiff',
            carbon_path='一切在岛:.background:background.tiff'))
    with DSStore.open(str(target), 'w+') as store:
        store['.']['vSrn'] = ('long', 1)
        store['.']['icvl'] = ('type', b'icnv')
        # dmgbuild writes icvl, but vstl is Finder's persisted "Always open in"
        # selection. Without it an existing Finder window can retain list view.
        # Keep both; never alter the recipient's global Finder preferences.
        store['.']['vstl'] = ('type', b'icnv')
        store['.']['bwsp'] = {
            'WindowBounds': BOUNDS,
            'ShowToolbar': False, 'ShowStatusBar': False, 'ShowPathbar': False,
            'ShowSidebar': False, 'ContainerShowSidebar': False,
            'ShowTabView': False, 'PreviewPaneVisibility': False, 'SidebarWidth': 0,
        }
        store['.']['icvp'] = {
            'viewOptionsVersion': 1, 'backgroundType': 2, 'backgroundImageAlias': background.to_bytes(),
            'backgroundColorRed': 0.97, 'backgroundColorGreen': 0.98, 'backgroundColorBlue': 1.0,
            'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'gridSpacing': 100.0,
            'arrangeBy': 'none', 'showIconPreview': False, 'showItemInfo': False,
            'labelOnBottom': True, 'textSize': 14.0, 'iconSize': 96.0,
            'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
        }
        for name, position in POSITIONS.items():
            store[name]['Iloc'] = position
    # Independently decode what was written, before approving its fixed digest.
    with DSStore.open(str(target), 'r') as store:
        assert store['.']['icvl'] == (b'type', b'icnv')
        assert store['.']['vstl'] == (b'type', b'icnv')
        assert store['.']['bwsp']['WindowBounds'] == BOUNDS
        assert store['.']['icvp']['iconSize'] == 96.0
        # Finder rejects the entire icon-view dictionary above 100.
        assert 0 < store['.']['icvp']['gridSpacing'] <= 100
        assert all(store[name]['Iloc'] == position for name, position in POSITIONS.items())
    value = {'version': 3, 'appName': APP_NAME, 'defaultView': 'icon',
             'alwaysOpenInIconView': True,
             'windowWidth': 820, 'windowHeight': 674, 'iconSize': 96,
             'positions': POSITIONS, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
             'background': 'background.tiff',
             'backgroundSha256': hashlib.sha256((output/'background.tiff').read_bytes()).hexdigest(),
             'generator': 'ds_store==1.3.1 / mac_alias==2.2.2'}
    metadata.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    print(str(target))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
