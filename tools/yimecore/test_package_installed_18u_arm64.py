"""Offline synthetic package checks, not an ARM64 build or execution."""
import json
from pathlib import Path
import shutil
import struct
import unittest
from unittest.mock import patch
import zipfile
import package_installed_18u as p
import test_assemble_installed_18u as fixtures

class Arm64PackageTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PayloadTests()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.work = self.f.root / 'work'
        self.sig = self.f.root / 'signature.json'
        self.source = 'b' * 40
        self.addCleanup(patch.stopall)
        for name in ('LAYOUT_SHA', 'DICTIONARY_SHA'):
            patch.object(p.a, name, getattr(fixtures.a, name)).start()
        descriptor = self.f.repo / p.a.RESOURCES['source/tools/yimecore/18u-touch-product.json']
        obj = json.loads(descriptor.read_text())
        obj['scope'] = {'architecture': 'x64'}
        descriptor.write_text(json.dumps(obj))
        obj['scope'] = {'architecture': 'arm64'}
        (self.f.repo / 'tools/yimecore/18u-touch-product-arm64.json').write_text(json.dumps(obj))
        rows = []
        for rel, (kind, name) in p.a.binary_map('arm64').items():
            path = (self.f.native if kind == 'native' else self.f.go) / name
            raw = bytearray(path.read_bytes())
            struct.pack_into('<H', raw, 68, 0xaa64)
            path.write_bytes(raw)
            rows.append({'path': 'payload/' + rel, **p.a.digest(path), 'status': 'NotSigned', 'signerThumbprint': None})
        self.sig.write_text(json.dumps({'schema':'installed-18u-signatures-v1','sourceCommit':self.source,'files':rows}))
        for name in p.INSTALLER:
            file = self.f.repo / 'installer/simple' / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('synthetic installer ' + name)

    def runner(self, command, **kwargs):
        args = json.loads(Path(command[-1]).read_text())
        self.assertEqual(args['Target'], 'windows-arm64')
        out = Path(args['OutputRoot'])
        shutil.copytree(args['PayloadRoot'], out / 'payload')
        for name in p.INSTALLER:
            shutil.copyfile(self.f.repo / 'installer/simple' / name, out / name)
        rows = [{'path':name, **digest} for name,digest in p.inventory(out / 'payload').items()]
        manifest = {'format':'yime-simple-package-18u-1','product':'yimecore-18u','version':p.VERSION,
                    'target':'windows-arm64','host_architecture':'arm64','tsf64_architecture':'arm64','files':rows}
        (out / 'product-package.json').write_text(json.dumps(manifest))

    def build(self, runner=None):
        return p.build(self.f.repo, self.f.native, self.f.go, self.f.data, self.work,
                       self.sig, self.source, runner=runner or self.runner, architecture='arm64')

    def test_exact_arm64_zip(self):
        result = self.build()
        archive = self.work / 'YimeCore-18u-0.1.0-18u-test.6-windows-arm64.zip'
        self.assertEqual(result['zip'], archive.name)
        self.assertEqual(result['sha256'], p.a.digest(archive)['sha256'])
        with zipfile.ZipFile(archive) as z:
            evidence = json.loads(z.read('package-evidence.json'))
            descriptor = json.loads(z.read('payload/installed-18u-product.json'))
            self.assertEqual(evidence['architecture'], 'native-arm64')
            self.assertEqual(descriptor['architecture'], 'native-arm64')
            self.assertIn('payload/arm64/YimeTextService18u.dll', z.namelist())
            self.assertNotIn('payload/x64/YimeTextService18u.dll', z.namelist())
            self.assertFalse(evidence['installedHostAcceptance'])

    def test_reject_mixed_target_manifest(self):
        def wrong(*args, **kwargs):
            self.runner(*args, **kwargs)
            path = self.work / 'package/product-package.json'
            obj = json.loads(path.read_text())
            obj['host_architecture'] = 'amd64'
            path.write_text(json.dumps(obj))
        with self.assertRaisesRegex(ValueError, 'manifest identity'):
            self.build(wrong)
        self.assertFalse((self.work / 'YimeCore-18u-0.1.0-18u-test.6-windows-arm64.zip').exists())

if __name__ == '__main__':
    unittest.main()
