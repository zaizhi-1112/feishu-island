import importlib.util
from pathlib import Path
import unittest
import tempfile
import plistlib
spec = importlib.util.spec_from_file_location('package_pilot', Path(__file__).resolve().parents[1]/'scripts/package-pilot.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
class DistributionChecks(unittest.TestCase):
    def test_rejects_runtime_material(self):
        for name in ['Contents/Resources/workspace.json','Contents/Resources/auth.json','Contents/Helpers/config.json','Contents/Resources/.env','Contents/Resources/BrowserBridge/chrome-reader/token.json','Contents/Resources/SettingsWeb/config.json','Contents/Resources/ThirdPartyLicenses/auth.json','Contents/Resources/ThirdPartyLicenses/.env','Contents/MacOS/other']:
            with self.subTest(name=name): self.assertFalse(m.allowed(Path(name)))
    def test_accepts_only_known_runtime_assets(self):
        for name in ['Contents/Info.plist','Contents/Resources/AppIcon.icns','Contents/MacOS/YuIsland','Contents/Helpers/lark-cli','Contents/Resources/SettingsWeb/app.js','Contents/Resources/BrowserBridge/chrome-reader/manifest.json','Contents/Resources/ThirdPartyLicenses/LICENSE.txt']:
            with self.subTest(name=name): self.assertTrue(m.allowed(Path(name)))
    def test_required_icon_and_unexpected_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)/'Test.app'
            files = {'Contents/MacOS/YuIsland', 'Contents/Resources/AppIcon.icns'}
            files |= {'Contents/Helpers/'+name for name in m.HELPERS}
            files |= {'Contents/Resources/BrowserBridge/chrome-reader/'+name for name in m.EXTENSION_FILES}
            for name in files:
                target=app/name; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(b'synthetic fixture')
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.zaizhi.feishu-island.preview'}))
            m.inspect(app)
            icon=app/'Contents/Resources/AppIcon.icns'
            icon.rename(Path(directory)/'saved-icon')
            with self.assertRaises(ValueError): m.inspect(app)
            (Path(directory)/'saved-icon').rename(icon)
            (app/'Contents/Resources/auth.json').write_text('{}')
            with self.assertRaises(ValueError): m.inspect(app)
if __name__ == '__main__': unittest.main()
