# Installer artwork

`background.html` is the editable 820 × 640 pt source. `first-open-warning.png` is the actual macOS 26.4.1 dialog, without personal content. The System Settings panel in the artwork is an illustrated location guide. Apple reference: https://support.apple.com/zh-cn/102445.

Render the HTML at 2× (1640 × 1280 px), excluding browser extension overlays, then encode TIFF with a logical size of 820 × 640 pt. Refresh `backgroundSha256` in `layout.json`. The Finder window is 820 × 674 pt to leave room for its title bar.

`generate-dmg-layout.py` uses `ds_store==1.3.1` and `mac_alias==2.2.2` in an isolated Python environment. Choose a fresh output directory containing the TIFF, inspect the generated template, then replace the template and metadata together. **Keep gridSpacing at or below 100:** Finder silently ignores the entire icon-view dictionary above that value. See https://dmgbuild.readthedocs.io/en/latest/settings.html#grid-spacing.

`package-pilot.py` binds the background alias to the actual writable disk image before read-only conversion. It audits the complete app, image, background and per-volume layout hashes. Verify the resulting DMG in Finder, including footer visibility; file existence and a successful build are not visual acceptance.
