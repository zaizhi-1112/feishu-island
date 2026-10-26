#!/usr/bin/env python3
"""Hosted help styles obey CSP while the offline original remains self-contained."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts/package-auth-service.py'
SOURCE=ROOT/'Distribution/开始使用.html'

class HostedHelpTests(unittest.TestCase):
    def stage(self,html):
        directory=Path(tempfile.mkdtemp(prefix='island-hosted-help-test-'))
        download=directory/'download';download.mkdir()
        (download/'index.html').write_text('<!doctype html><title>Synthetic</title>')
        (download/'SHA256SUMS').write_text('synthetic')
        (download/'start.html').write_text(html)
        output=directory/'service'
        result=subprocess.run(['python3',str(SCRIPT),str(download),str(output)],capture_output=True,text=True)
        return result,output

    def test_extracts_exact_css_only_in_hosted_copy(self):
        before=SOURCE.read_bytes();html=before.decode()
        result,output=self.stage(html)
        self.assertEqual(result.returncode,0,result.stderr)
        hosted=(output/'public/start.html').read_text()
        self.assertIn('<link rel="stylesheet" href="start.css">',hosted)
        self.assertNotIn('<style',hosted.lower())
        css=re.findall(r'<style>(.*?)</style>',html,flags=re.I|re.S)
        self.assertEqual((output/'public/start.css').read_text(),css[0]+'\n')
        self.assertEqual(SOURCE.read_bytes(),before)
        self.assertIn('<style>',SOURCE.read_text())

    def test_product_icon_survives_service_overlay(self):
        result,output=self.stage(SOURCE.read_text())
        self.assertEqual(result.returncode,0,result.stderr)
        product=(ROOT/'Distribution/site/icon.png').read_bytes()
        self.assertEqual((ROOT/'AuthService/public/icon.png').read_bytes(),product)
        self.assertEqual((output/'public/icon.png').read_bytes(),product)

    def test_unsupported_style_shape_stops_packaging(self):
        result,_=self.stage('<style media="print">p{color:red}</style><p>synthetic</p>')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Expected one plain inline style block',result.stderr)

if __name__=='__main__':unittest.main()
