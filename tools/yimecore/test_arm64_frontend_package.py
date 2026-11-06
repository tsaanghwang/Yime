"""ARM64 complete-package contracts. Synthetic PE fixtures are never executed."""
import json
from pathlib import Path
import shutil
import struct
import unittest
from unittest.mock import patch
import zipfile

import assemble_installed_18u as a
import package_installed_18u as package
import test_installed_frontend_package as frontend_fixtures


class ARM64FrontendPackageTests(unittest.TestCase):
    def setUp(self):
        self.frontend = frontend_fixtures.FrontendTests()
        self.frontend.setUp()
        self.addCleanup(self.frontend.doCleanups)
        self.f = self.frontend.fixture
        for module in (a, package.a):
            for name, value in (('LAYOUT_SHA', self.f.layout), ('DICTIONARY_SHA', self.f.dictionary)):
                replacement = patch.object(module, name, value)
                replacement.start()
                self.addCleanup(replacement.stop)
        self.front = self.frontend.front
        for directory in (self.f.native, self.f.go, self.front):
            for path in directory.glob('*.exe'):
                self.machine(path, 0xaa64)
            for path in directory.glob('*.dll'):
                self.machine(path, 0xaa64)
        source = self.f.repo / 'tools/yimecore/18u-touch-product.json'
        canonical = json.loads(source.read_text())
        canonical['scope'] = {'architecture': 'x64'}
        source.write_text(json.dumps(canonical))
        canonical['scope']['architecture'] = 'arm64'
        self.arm_descriptor = source.with_name('18u-touch-product-arm64.json')
        self.arm_descriptor.write_text(json.dumps(canonical))
        self.frontend.info['architecture'] = 'windows-arm64'
        self.frontend.inventory()

    @staticmethod
    def machine(path, machine):
        raw = bytearray(path.read_bytes())
        struct.pack_into('<H', raw, struct.unpack_from('<I', raw, 60)[0] + 4, machine)
        path.write_bytes(raw)

    def assemble(self):
        return a.assemble(self.f.repo, self.f.native, self.f.go, self.f.data,
                          self.f.out, 'b' * 40, self.front, 'arm64')

    def test_complete_arm_manifest_and_payload(self):
        manifest = self.assemble()
        self.assertEqual(manifest['schema'], 'installed-18u-product-v1')
        self.assertEqual(manifest['architecture'], 'native-arm64')
        self.assertEqual(len(manifest), 9)
        self.assertIs(manifest['autostart'], False)
        names = {row['path'] for row in manifest['files']}
        self.assertIn('arm64/YimeTextService18u.dll', names)
        self.assertIn('frontend/YimeTouchKeyboard.exe', names)
        self.assertIn('source/tools/yimecore/18u-touch-product-arm64.json', names)
        self.assertFalse(any(name.startswith('x64/') for name in names))

    def test_each_foreign_binary_is_rejected_before_output(self):
        paths = [self.f.native / 'YimeTextService18u.dll', self.f.go / 'YimeBroker18u.exe',
                 self.front / 'YimeTouchKeyboard.exe']
        for path in paths:
            for machine in (0x8664, 0xa641, 0x14c):
                with self.subTest(path=path.name, machine=machine):
                    self.machine(path, machine)
                    self.frontend.inventory()
                    with self.assertRaisesRegex(ValueError, 'native ARM64 PE'):
                        self.assemble()
                    self.assertFalse(self.f.out.exists())
                    self.machine(path, 0xaa64)
                    self.frontend.inventory()

    def test_other_frontend_architecture_refused(self):
        self.frontend.info['architecture'] = 'windows-amd64'
        self.frontend.inventory()
        with self.assertRaisesRegex(ValueError, 'matching-source arm64'):
            self.assemble()

    def test_arm_descriptor_cannot_fork_identity_or_resources(self):
        original = json.loads(self.arm_descriptor.read_text())
        for field in ('identity', 'data', 'scope'):
            changed = json.loads(json.dumps(original))
            changed[field]['extra'] = True
            self.arm_descriptor.write_text(json.dumps(changed))
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'beyond architecture'):
                self.assemble()
            self.assertFalse(self.f.out.exists())

    def test_old_broker_frontend_not_accepted_as_v2(self):
        path = self.front / 'YimeTouchKeyboard.exe'
        path.write_bytes(path.read_bytes().replace(b'Yime18u.Frontend.v2.', b'YimeBroker.18uTouch.v1.desktop-'))
        self.frontend.inventory()
        with self.assertRaisesRegex(ValueError, 'v2 binary protocol marker missing'):
            self.assemble()

    def test_arm_delivery_requires_complete_frontend(self):
        with self.assertRaisesRegex(ValueError, 'complete matching-source v2'):
            package.build(self.f.repo, self.f.native, self.f.go, self.f.data,
                          self.f.root / 'work', self.f.root / 'missing', 'b'*40, architecture='arm64')

    def test_arm_archive_target_signatures_and_scope(self):
        for name in package.INSTALLER:
            path = self.f.repo / 'installer/simple' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic installer, never executed')
        rows = []
        for dest, (kind, name) in a.binary_map('arm64').items():
            path = (self.f.native if kind == 'native' else self.f.go) / name
            rows.append(dict(path='payload/' + dest, **a.digest(path), status='NotSigned', signerThumbprint=None))
        rows.append(dict(path='payload/frontend/YimeTouchKeyboard.exe',
                         **a.digest(self.front / 'YimeTouchKeyboard.exe'), status='NotSigned', signerThumbprint=None))
        signature = self.f.root / 'signatures.json'
        signature.write_text(json.dumps(dict(schema='installed-18u-signatures-v1', sourceCommit='b'*40, files=rows)))

        def runner(command, **kwargs):
            args = json.loads(Path(command[-1]).read_text())
            self.assertEqual(args['Target'], 'windows-arm64')
            self.assertEqual(args['Version'], '0.2.0-18u-arm64.7')
            out = Path(args['OutputRoot'])
            shutil.copytree(args['PayloadRoot'], out / 'payload')
            for name in package.INSTALLER:
                shutil.copyfile(self.f.repo / 'installer/simple' / name, out / name)
            entries = [dict(path=name, **record) for name, record in package.inventory(out / 'payload').items()]
            (out / 'product-package.json').write_text(json.dumps(dict(
                format='yime-simple-package-18u-1', product='yimecore-18u', version=args['Version'],
                target='windows-arm64', host_architecture='arm64', tsf64_architecture='arm64', files=entries)))

        work = self.f.root / 'work'
        result = package.build(self.f.repo, self.f.native, self.f.go, self.f.data, work,
                               signature, 'b'*40, runner=runner, frontend=self.front, architecture='arm64')
        self.assertEqual(result['zip'], 'YimeCore-18u-0.2.0-18u-arm64.7-windows-arm64.zip')
        with zipfile.ZipFile(work / result['zip']) as archive:
            evidence = json.loads(archive.read('package-evidence.json'))
            self.assertEqual(evidence['architecture'], 'native-arm64')
            self.assertEqual(evidence['version'], '0.2.0-18u-arm64.7')
            self.assertEqual(evidence['frontendProtocol'], a.FRONTEND_PROTOCOL)
            self.assertFalse(evidence['installationExecuted'])
            self.assertFalse(evidence['installedHostAcceptance'])
            self.assertEqual(len(json.loads(archive.read('signatures.json'))['files']), 6)
            self.assertNotIn('payload/bin/YimeTouchKeyboard.exe', archive.namelist())
            self.assertIn('旧 ARM .5', archive.read('README.zh-CN.md').decode('utf-8'))
            self.assertIn('ARM64 .7', archive.read('README.zh-CN.md').decode('utf-8'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
