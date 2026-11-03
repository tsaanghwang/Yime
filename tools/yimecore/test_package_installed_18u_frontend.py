"""Complete frontend packaging contracts; no installed product or PE is executed."""
import json
from pathlib import Path
import shutil
import struct
import unittest
import zipfile

import package_installed_18u as p
import test_package_installed_18u_arm64 as arm64_fixture


class FrontendPackageTests(unittest.TestCase):
    def setUp(self):
        self.fixture = arm64_fixture.Arm64PackageTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.f = self.fixture.f
        self.work = self.fixture.work
        for arch in ('x64', 'arm64'):
            path = self.f.repo / ('tools/yimecore/18u-touch-product' + ('-arm64' if arch == 'arm64' else '') + '.json')
            doc = json.loads(path.read_text())
            doc.update(schema_version='yimecore-18u-touch-product-v2', installable=True)
            doc['scope'].update(installed_frontend=True, languages=['CN', 'EN'],
                                modes=['full', 'variable', 'shorthand'], capabilities=p.a.FRONTEND_CAPABILITIES)
            doc['data']['dictionary_sha256_by_mode'] = {
                mode: p.a.digest(self.f.data / ('yime_' + mode + '.dict.yaml'))['sha256']
                for mode in ('full', 'variable', 'shorthand')}
            path.write_text(json.dumps(doc))
        gui = self.f.go / 'YimeTouchKeyboard.exe'
        shutil.copyfile(self.f.go / 'YimeBroker18u.exe', gui)
        for src in p.a.FRONTEND_RESOURCES.values():
            path = self.f.repo / src
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic frontend resource')
        sig = json.loads(self.fixture.sig.read_text())
        sig['files'].append({'path': 'payload/bin/YimeTouchKeyboard.exe', **p.a.digest(gui),
                             'status': 'NotSigned', 'signerThumbprint': None})
        self.fixture.sig.write_text(json.dumps(sig))

    def runner(self, command, **kwargs):
        self.fixture.runner(command, **kwargs)
        path = self.work / 'package/product-package.json'
        doc = json.loads(path.read_text())
        args = json.loads(Path(command[-1]).read_text())
        self.assertEqual(args['Version'], p.FRONTEND_VERSION)
        doc['version'] = args['Version']
        path.write_text(json.dumps(doc))

    def build(self):
        return p.build(self.f.repo, self.f.native, self.f.go, self.f.data, self.work,
                       self.fixture.sig, self.fixture.source, runner=self.runner,
                       architecture='arm64', frontend=True)

    def test_complete_three_mode_frontend_and_gui_signature(self):
        result = self.build()
        with zipfile.ZipFile(self.work / result['zip']) as archive:
            descriptor = json.loads(archive.read('payload/installed-18u-product.json'))
            self.assertEqual(descriptor['schema'], 'installed-18u-product-v2')
            self.assertEqual(descriptor['modes'], ['full', 'variable', 'shorthand'])
            self.assertEqual(descriptor['languages'], ['CN', 'EN'])
            self.assertTrue(descriptor['autostart'])
            self.assertNotIn('mode', descriptor)
            self.assertNotIn('language', descriptor)
            expected = {'payload/' + name for name in p.a.FRONTEND_RESOURCES}
            expected.add('payload/bin/YimeTouchKeyboard.exe')
            self.assertTrue(expected.issubset(archive.namelist()))
            self.assertEqual(len(json.loads(archive.read('signatures.json'))['files']), 6)

    def test_gui_required_before_output(self):
        (self.f.go / 'YimeTouchKeyboard.exe').unlink()
        with self.assertRaisesRegex(ValueError, 'missing regular input'):
            self.build()
        self.assertFalse(self.work.exists())

    def test_emulated_gui_rejected(self):
        gui = self.f.go / 'YimeTouchKeyboard.exe'
        raw = bytearray(gui.read_bytes())
        struct.pack_into('<H', raw, 68, 0x8664)
        gui.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, 'native ARM64'):
            self.build()

    def test_v1_scope_cannot_be_relabelled_complete(self):
        for suffix in ('', '-arm64'):
            path = self.f.repo / ('tools/yimecore/18u-touch-product' + suffix + '.json')
            doc = json.loads(path.read_text())
            doc['installable'] = False
            path.write_text(json.dumps(doc))
        with self.assertRaisesRegex(ValueError, 'frontend source scope'):
            self.build()

    def test_missing_gui_signature_rejected(self):
        sig = json.loads(self.fixture.sig.read_text())
        sig['files'].pop()
        self.fixture.sig.write_text(json.dumps(sig))
        with self.assertRaisesRegex(ValueError, 'signature inventory'):
            self.build()


if __name__ == '__main__':
    unittest.main()
