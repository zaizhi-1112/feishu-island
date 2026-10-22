import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('package_pilot', Path(__file__).resolve().parents[1]/'scripts/package-pilot.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
class DistributionChecks(unittest.TestCase):
    def test_rejects_runtime_material(self):
        for name in ['Contents/Resources/workspace.json','Contents/Resources/auth.json','Contents/Helpers/config.json','Contents/Resources/.env','Contents/Resources/BrowserBridge/chrome-reader/token.json','Contents/Resources/SettingsWeb/config.json','Contents/Resources/ThirdPartyLicenses/auth.json','Contents/Resources/ThirdPartyLicenses/.env','Contents/MacOS/other']:
            with self.subTest(name=name): self.assertFalse(m.allowed(Path(name)))
    def test_accepts_only_known_runtime_assets(self):
        for name in ['Contents/Info.plist','Contents/MacOS/YuIsland','Contents/Helpers/lark-cli','Contents/Resources/SettingsWeb/app.js','Contents/Resources/BrowserBridge/chrome-reader/manifest.json','Contents/Resources/ThirdPartyLicenses/LICENSE.txt']:
            with self.subTest(name=name): self.assertTrue(m.allowed(Path(name)))
if __name__ == '__main__': unittest.main()
