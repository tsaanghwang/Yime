"""Synthetic frontend assembly contracts; never executes generated PE fixtures."""
import json
import shutil
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile
import package_installed_18u as package
import test_assemble_installed_18u as fixtures


class FrontendTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.PayloadTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        f = self.fixture
        self.front = f.root / 'frontend'
        self.front.mkdir()
        shutil.copyfile(f.native / 'YimeTextService18u.dll', self.front / 'YimeTouchKeyboard.exe')
        for name in fixtures.a.DATA:
            target = self.front / 'data' / name
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(f.data / name, target)
        for name in ('prototypes/touch-terminal/data/physical-layout.json',
                     'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'):
            target = self.front / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f.repo / name, target)
        self.info = dict(scope='installed-18u-tsf-frontend-candidate', sourceCommit='b'*40,
                         sourceChanges=False, architecture='windows-amd64', sendInputFallback=False)
        self.inventory()

    def inventory(self):
        self.info['files'] = {p.relative_to(self.front).as_posix(): fixtures.a.digest(p)['sha256']
                              for p in self.front.rglob('*') if p.is_file() and p.name != 'manifest.json'}
        (self.front / 'manifest.json').write_text(json.dumps(self.info), encoding='utf-8')

    def build(self):
        f = self.fixture
        return fixtures.a.assemble(f.repo, f.native, f.go, f.data, f.out, 'b'*40, self.front)

    def test_complete_inventory(self):
        rows = self.build()['files']
        self.assertIn('frontend/YimeTouchKeyboard.exe', {r['path'] for r in rows})
        for row in rows:
            self.assertEqual(fixtures.a.digest(self.fixture.out / row['path'])['sha256'], row['sha256'])

    def test_dirty_or_other_source_refused(self):
        for field, value in [('sourceChanges', True), ('sourceCommit', 'c'*40), ('sendInputFallback', True), ('architecture', 'windows-arm64')]:
            with self.subTest(field=field):
                original = self.info[field]
                self.info[field] = value
                self.inventory()
                with self.assertRaisesRegex(ValueError, 'matching-source'):
                    self.build()
                self.assertFalse(self.fixture.out.exists())
                self.info[field] = original

    def test_changed_executable_refused(self):
        (self.front / 'YimeTouchKeyboard.exe').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'file mismatch'):
            self.build()

    def test_self_consistent_wrong_dictionary_refused(self):
        (self.front / 'data/yime_full.dict.yaml').write_text('wrong')
        self.inventory()
        with self.assertRaisesRegex(ValueError, 'frontend locked resource mismatch'):
            self.build()

    def test_self_consistent_wrong_projection_refused(self):
        (self.front / 'prototypes/touch-terminal/data/physical-layout.json').write_text('{}')
        self.inventory()
        with self.assertRaisesRegex(ValueError, 'frontend projection mismatch'):
            self.build()

    def test_extra_file_refused(self):
        (self.front / 'extra').write_text('unexpected')
        with self.assertRaisesRegex(ValueError, 'inventory mismatch'):
            self.build()

    def test_test7_archive_and_six_signatures(self):
        f = self.fixture
        for name in ('LAYOUT_SHA', 'DICTIONARY_SHA'):
            self.addCleanup(patch.stopall)
            patch.object(package.a, name, getattr(fixtures.a, name)).start()
        for name in package.INSTALLER:
            target = f.repo / 'installer/simple' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('synthetic installer, never executed')
        signatures = []
        for dest, (kind, name) in fixtures.a.BINARIES.items():
            path = (f.native if kind == 'native' else f.go) / name
            signatures.append(dict(path='payload/' + dest, **fixtures.a.digest(path), status='NotSigned', signerThumbprint=None))
        signatures.append(dict(path='payload/frontend/YimeTouchKeyboard.exe', **fixtures.a.digest(self.front / 'YimeTouchKeyboard.exe'), status='NotSigned', signerThumbprint=None))
        signature_file = f.root / 'signatures.json'
        signature_file.write_text(json.dumps(dict(schema='installed-18u-signatures-v1', sourceCommit='b'*40, files=signatures)))

        def runner(command, **kwargs):
            args = json.loads(Path(command[-1]).read_text())
            self.assertEqual(args['Version'], '0.1.0-18u-test.8')
            output = Path(args['OutputRoot'])
            shutil.copytree(args['PayloadRoot'], output / 'payload')
            for name in package.INSTALLER:
                shutil.copyfile(f.repo / 'installer/simple' / name, output / name)
            rows = [dict(path=name, **record) for name, record in package.inventory(output / 'payload').items()]
            (output / 'product-package.json').write_text(json.dumps(dict(format='yime-simple-package-18u-1', product='yimecore-18u', version=args['Version'], target='windows-amd64', host_architecture='amd64', tsf64_architecture='x64', files=rows)))

        work = f.root / 'work'
        receipt = package.build(f.repo, f.native, f.go, f.data, work, signature_file, 'b'*40, runner=runner, frontend=self.front)
        with zipfile.ZipFile(work / receipt['zip']) as archive:
            self.assertIn('payload/frontend/YimeTouchKeyboard.exe', archive.namelist())
            self.assertEqual(len(json.loads(archive.read('signatures.json'))['files']), 6)
            evidence = json.loads(archive.read('package-evidence.json'))
            self.assertEqual(evidence['version'], '0.1.0-18u-test.8')
            self.assertFalse(evidence['installationExecuted'])
            self.assertFalse(evidence['installedHostAcceptance'])


if __name__ == '__main__':
    unittest.main()
