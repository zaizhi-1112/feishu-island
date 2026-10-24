#!/usr/bin/env python3
"""Generate the reviewed Finder layout template, without driving Finder or mounting a disk.

Only regeneration needs the isolated build dependency ds_store==1.3.1. Normal packaging
uses the checked-in template and standard-library hash validation. To change the layout,
write into a new --output directory, inspect it, then update both template and metadata.
Field meanings follow the upstream ds_store/dmgbuild implementations:
https://ds-store.readthedocs.io/en/latest/
https://github.com/dmgbuild/dmgbuild/blob/main/src/dmgbuild/core.py
https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
"""
import argparse
import hashlib
import json
from pathlib import Path
from ds_store import DSStore

APP_NAME = '飞书工作岛预览版.app'
BOUNDS = '{{160, 140}, {600, 360}}'
POSITIONS = {APP_NAME: (150, 160), 'Applications': (450, 160)}


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    target = output/'FinderLayout.dsstore'
    metadata = output/'layout.json'
    if target.exists() or metadata.exists():
        raise ValueError('Choose a fresh output directory; preserve previous layout templates')
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
            'viewOptionsVersion': 1, 'backgroundType': 1,
            'backgroundColorRed': 0.97, 'backgroundColorGreen': 0.98, 'backgroundColorBlue': 1.0,
            'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'gridSpacing': 180.0,
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
        assert all(store[name]['Iloc'] == position for name, position in POSITIONS.items())
    value = {'version': 2, 'appName': APP_NAME, 'defaultView': 'icon',
             'alwaysOpenInIconView': True,
             'windowWidth': 600, 'windowHeight': 360, 'iconSize': 96,
             'positions': POSITIONS, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
             'generator': 'ds_store==1.3.1'}
    metadata.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    print(str(target))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
