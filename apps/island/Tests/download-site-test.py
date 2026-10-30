import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('download_site', Path(__file__).resolve().parents[1]/'scripts/package-download-site.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


class DownloadSiteChecks(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='island-site-synthetic-'))
        (self.root/'Resources').mkdir()
        (self.root/'Distribution/site').mkdir(parents=True)
        (self.root/'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '99'}))
        self.name = 'feishu-island-1.2.3-build99-arm64.dmg'
        self.package = self.root/self.name; self.package.write_bytes(b'synthetic dmg')
        (self.root/'Distribution/site/index.html').write_text(f'<meta content="1.2.3/99/arm64"><a href="{self.name}">Download</a>')
        guide = self.root/'Distribution/开始使用.html'; guide.write_text('1.2.3 · build99')
        (self.root/'Distribution/released-packages.json').write_text(json.dumps(['feishu-island-1.2.2-build98-arm64.dmg']))
        self.manifest = {'version':'1.2.3','build':'99','architectures':['arm64'],'status':'pilot-preparation','format':'dmg',
                         'archive':self.name,'sha256':hashlib.sha256(self.package.read_bytes()).hexdigest(),
                         'includesPersonalCredentials':False,'browserExtensionEmbedded':False,
                         'verification':dict.fromkeys(['imageIntegrity','readOnlyMounted','bundleHashesMatch','signatureValid','detached'],True),
                         'files':[{'path':'Contents/Resources/开始使用.html','sha256':hashlib.sha256(guide.read_bytes()).hexdigest()}]}

    def test_verified_release_and_old_download_urls(self):
        name, _, aliases = m.validate(self.package, self.manifest, self.root)
        self.assertEqual(name, self.name)
        self.assertEqual(aliases, {'feishu-island-1.2.2-build98-arm64.dmg':self.name})

    def test_rejects_mixed_versions_credentials_and_incomplete_verification(self):
        variants = [('build','98'), ('sha256','wrong'), ('includesPersonalCredentials',True), ('browserExtensionEmbedded',True), ('verification',{})]
        for key, value in variants:
            with self.subTest(key=key):
                manifest = copy.deepcopy(self.manifest); manifest[key] = value
                with self.assertRaises(ValueError): m.validate(self.package, manifest, self.root)

    def test_rejects_package_too_large_for_backend_upload(self):
        with self.package.open('wb') as file: file.truncate(m.MAX_DMG_BYTES+1)
        with self.assertRaisesRegex(ValueError,'upload budget'):
            m.validate(self.package,self.manifest,self.root)

    def test_web_only_download_has_its_own_bounded_budget(self):
        with self.package.open("wb") as file: file.truncate(m.MAX_DMG_BYTES+1)
        self.manifest["sha256"] = hashlib.sha256(self.package.read_bytes()).hexdigest()
        m.validate(self.package,self.manifest,self.root,web_only=True)
        with self.assertRaisesRegex(ValueError,"upload budget"):
            m.validate(self.package,self.manifest,self.root)
        with self.package.open("wb") as file: file.truncate(m.MAX_REMOTE_DMG_BYTES+1)
        with self.assertRaisesRegex(ValueError,"build download budget"):
            m.validate(self.package,self.manifest,self.root,web_only=True)

    def test_rejects_changed_bundled_instructions(self):
        (self.root/'Distribution/开始使用.html').write_text('1.2.3 · build99 changed guide')
        with self.assertRaisesRegex(ValueError,'bundled'): m.validate(self.package,self.manifest,self.root)

    def test_rejects_legacy_alias_path_escape(self):
        (self.root/'Distribution/released-packages.json').write_text('["../private.json"]')
        with self.assertRaisesRegex(ValueError,'legacy'): m.validate(self.package,self.manifest,self.root)

    def test_hosted_guide_preserves_content_under_self_only_csp(self):
        source = (m.ROOT/'Distribution/开始使用.html').read_text()
        html, css, js = m.web_guide(source)
        self.assertNotIn('<style>', html)
        self.assertNotIn('onclick=', html)
        self.assertNotIn(' style=', html)
        self.assertIn('href="start.css"', html)
        self.assertIn('src="start.js"', html)
        self.assertIn('data-reading-size="23px"', html)
        self.assertIn('font-size:21px', css)
        self.assertIn('addEventListener', js)
        self.assertIn('仍要打开', html)
        self.assertIn('data:image/png;base64,', html)

    def test_unhandled_inline_behavior_stops_guide_publication(self):
        with self.assertRaisesRegex(ValueError, 'inline behavior'):
            m.web_guide('<head><style>body{}</style></head><button onclick="unexpected()">Go</button>')

    def test_remote_asset_must_match_audited_bytes_and_release(self):
        page = (f'<a href="{self.name}" download="一切在岛.dmg">Download</a>'
                '<p class="download-alternative"><a href="https://github.com/owner/repo/releases/tag/v1.2.3-build99">GitHub</a></p>')
        asset = {'state':'uploaded', 'name':self.name, 'size':self.package.stat().st_size,
                 'digest':'sha256:'+self.manifest['sha256'],
                 'browser_download_url':'https://github.com/owner/repo/releases/download/v1.2.3-build99/'+self.name}
        result = m.download_source(self.package, self.manifest, asset, page)
        self.assertEqual(result['sha256'], self.manifest['sha256'])
        self.assertEqual(result['url'], asset['browser_download_url'])
        for key, value in [('state','new'),('size',999),('digest','sha256:wrong'),('name','other.dmg'),
                           ('browser_download_url',asset['browser_download_url'].replace('build99/','build98/'))]:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError,'asset'):
                m.download_source(self.package, self.manifest, {**asset,key:value}, page)
        with self.assertRaisesRegex(ValueError,'named download'):
            m.download_source(self.package, self.manifest, asset, page.replace('download="一切在岛.dmg"','download'))


if __name__ == '__main__': unittest.main()
