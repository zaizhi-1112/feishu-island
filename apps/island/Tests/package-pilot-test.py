import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch, Mock
import tempfile
import plistlib
import json

spec = importlib.util.spec_from_file_location('package_pilot', Path(__file__).resolve().parents[1]/'scripts/package-pilot.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class DistributionChecks(unittest.TestCase):
    def fixture(self):
        # Retain generated fixtures; do not irreversibly remove filesystem content.
        directory = Path(tempfile.mkdtemp(prefix='island-package-synthetic-'))
        app = directory/'飞书工作岛预览版.app'
        files = {'Contents/MacOS/YuIsland', 'Contents/Resources/AppIcon.icns'}
        files |= {'Contents/Helpers/'+name for name in m.HELPERS}
        files |= m.CHECKIN_FILES
        files |= {'Contents/Resources/BrowserBridge/chrome-reader/'+name for name in m.EXTENSION_FILES}
        files |= {'Contents/Resources/ScreenReminder/'+name for name in m.REMINDER_FILES}
        for name in files:
            target = app/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'synthetic fixture')
        info = {'CFBundleIdentifier': 'local.zaizhi.feishu-island.preview',
                'CFBundleShortVersionString': '0.7.0', 'CFBundleVersion': '29',
                'LSMinimumSystemVersion': '15.0'}
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        m.install_layout(directory, app.name)
        return directory, app

    def test_rejects_runtime_material(self):
        for name in ['Contents/Resources/workspace.json', 'Contents/Resources/auth.json', 'Contents/Helpers/config.json', 'Contents/Resources/.env', 'Contents/Resources/BrowserBridge/chrome-reader/token.json', 'Contents/Resources/SettingsWeb/config.json', 'Contents/Resources/ThirdPartyLicenses/auth.json', 'Contents/Resources/ThirdPartyLicenses/.env', 'Contents/MacOS/other']:
            with self.subTest(name=name): self.assertFalse(m.allowed(Path(name)))

    def test_accepts_only_known_runtime_assets(self):
        for name in ['Contents/Info.plist', 'Contents/Resources/AppIcon.icns', 'Contents/MacOS/YuIsland', 'Contents/Helpers/lark-cli', 'Contents/Resources/SettingsWeb/app.js', 'Contents/Resources/BrowserBridge/chrome-reader/manifest.json', 'Contents/Resources/ThirdPartyLicenses/LICENSE.txt']:
            with self.subTest(name=name): self.assertTrue(m.allowed(Path(name)))

    def test_required_icon_and_unexpected_credentials(self):
        directory, app = self.fixture()
        m.inspect(app)
        icon = app/'Contents/Resources/AppIcon.icns'
        icon.rename(directory/'saved-icon')
        with self.assertRaises(ValueError): m.inspect(app)
        (directory/'saved-icon').rename(icon)
        (app/'Contents/Resources/auth.json').write_text('{}')
        with self.assertRaises(ValueError): m.inspect(app)

    def test_bundle_symlink_cannot_escape_audit(self):
        directory, app = self.fixture()
        (app/'Contents/Resources/personal').symlink_to(directory)
        with self.assertRaisesRegex(ValueError, 'symlinks'): m.inspect(app)

    def test_reminders_require_exact_packaged_media_and_reject_personal_videos(self):
        directory, app = self.fixture()
        m.inspect(app)
        source = app/'Contents/Resources/ScreenReminder/rick-portal.mov'
        source.rename(directory/'retained-video.mov')
        with self.assertRaisesRegex(ValueError, 'Required runtime'): m.inspect(app)
        for value in ['Contents/Resources/ScreenReminder/personal.mov', 'Contents/Resources/ScreenReminder/neko1.mov', 'Contents/Resources/ScreenReminder/ScreenReminderMedia/config.json']:
            self.assertFalse(m.allowed(Path(value)))

    def test_dmg_has_exactly_two_visible_items_and_embedded_extension(self):
        directory, app = self.fixture()
        info, entries = m.inspect(app)
        (directory/'Applications').symlink_to('/Applications', target_is_directory=True)
        m.inspect_volume(directory, app.name, info, entries)
        self.assertTrue(all((app/'Contents/Resources/BrowserBridge/chrome-reader'/name).is_file() for name in m.EXTENSION_FILES))
        (directory/'开始使用.html').write_text('synthetic')
        with self.assertRaisesRegex(ValueError, 'only the application'): m.inspect_volume(directory, app.name, info, entries)

    def test_dmg_rejects_wrong_install_target_hidden_material_and_changed_app(self):
        directory, app = self.fixture()
        info, entries = m.inspect(app)
        (directory/'Applications').symlink_to('/tmp', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'shortcut'): m.inspect_volume(directory, app.name, info, entries)
        (directory/'Applications').rename(directory/'wrong-shortcut')
        (directory/'Applications').symlink_to('/Applications', target_is_directory=True)
        (directory/'wrong-shortcut').rename(directory.parent/('saved-'+directory.name))
        (directory/'.env').write_text('synthetic')
        with self.assertRaisesRegex(ValueError, 'hidden material'): m.inspect_volume(directory, app.name, info, entries)
        (directory/'.env').rename(directory.parent/('fixture-'+directory.name))
        (app/'Contents/MacOS/YuIsland').write_bytes(b'changed synthetic binary')
        with self.assertRaisesRegex(ValueError, 'changed during packaging'): m.inspect_volume(directory, app.name, info, entries)

    def test_runtime_keeps_signature_and_helper_architecture_checks(self):
        _, app = self.fixture()
        with patch.object(m.subprocess, 'run') as run, patch.object(m.subprocess, 'check_output', return_value='arm64\n'):
            self.assertEqual(m.verify_runtime(app), ['arm64'])
            self.assertEqual(run.call_count, 2)
            self.assertEqual(run.call_args_list[1].args[0], ['codesign', '--verify', '--strict', str(app/'Contents/Helpers/WorkBuddyCheckin.app')])
        outputs = iter(['arm64', 'x86_64'])
        with patch.object(m.subprocess, 'run'), patch.object(m.subprocess, 'check_output', side_effect=lambda *a, **k: next(outputs)):
            with self.assertRaisesRegex(ValueError, 'architecture mismatch'): m.verify_runtime(app)

    def test_failed_mounted_audit_still_detaches_exact_mount(self):
        directory, app = self.fixture()
        mount = directory/'verification-mount'
        archive = directory/'synthetic.dmg'
        info, entries = m.inspect(app)
        reply = plistlib.dumps({'system-entities': [{'mount-point': str(mount), 'dev-entry': '/dev/diskSynthetic'}]})
        with patch.object(m.subprocess, 'run', return_value=Mock(stdout=reply)) as run, patch.object(m, 'inspect_volume', side_effect=ValueError('synthetic audit failure')):
            with self.assertRaisesRegex(ValueError, 'synthetic audit failure'):
                m.verify_dmg(archive, mount, app.name, info, entries, ['arm64'])
            self.assertEqual(run.call_args_list[-1].args[0], ['hdiutil', 'detach', str(mount)])
            attach = run.call_args_list[1].args[0]
            self.assertIn('-readonly', attach)
            self.assertIn('-nobrowse', attach)
            self.assertIn('-noautoopen', attach)

    def test_reviewed_icon_layout_is_pinned_to_app_and_both_positions(self):
        metadata, data = m.layout_template('飞书工作岛预览版.app')
        self.assertEqual(metadata['defaultView'], 'icon')
        self.assertEqual(metadata['version'], 2)
        self.assertTrue(metadata['alwaysOpenInIconView'])
        self.assertEqual((metadata['windowWidth'], metadata['windowHeight']), (600, 360))
        self.assertEqual(metadata['iconSize'], 96)
        self.assertEqual(metadata['positions']['飞书工作岛预览版.app'], [150, 160])
        self.assertEqual(metadata['positions']['Applications'], [450, 160])
        self.assertGreater(len(data), 100)
        with self.assertRaisesRegex(ValueError, 'name does not match'):
            m.layout_template('Renamed.app')

    def test_missing_or_changed_layout_stops_distribution(self):
        directory, app = self.fixture()
        info, entries = m.inspect(app)
        (directory/'Applications').symlink_to('/Applications', target_is_directory=True)
        m.inspect_volume(directory, app.name, info, entries)
        (directory/'.DS_Store').rename(directory.parent/('layout-'+directory.name))
        with self.assertRaisesRegex(ValueError, 'layout is missing or changed'):
            m.inspect_volume(directory, app.name, info, entries)
        (directory/'.DS_Store').write_bytes(b'synthetic changed layout')
        with self.assertRaisesRegex(ValueError, 'layout is missing or changed'):
            m.inspect_volume(directory, app.name, info, entries)
        corrupt = Path(tempfile.mkdtemp(prefix='island-layout-synthetic-'))
        (corrupt/'layout.json').write_text(json.dumps(json.loads((m.LAYOUT_DIR/'layout.json').read_text())))
        (corrupt/'FinderLayout.dsstore').write_bytes(b'synthetic changed template')
        with patch.object(m, 'LAYOUT_DIR', corrupt):
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                m.layout_template(app.name)


if __name__ == '__main__': unittest.main()
