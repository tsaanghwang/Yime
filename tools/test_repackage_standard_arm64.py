"""Small offline repack contracts; no PowerShell, installation or real payload execution."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

SPEC = importlib.util.spec_from_file_location('standard_repack', Path(__file__).parent / 'yimecore/repackage_standard_arm64.py')
repack = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repack)


class RepackTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo, self.original = self.root / 'repo', self.root / 'original'
        source = self.repo / 'installer/simple'
        source.mkdir(parents=True)
        (self.original / 'payload/bin').mkdir(parents=True)
        for name in (*repack.MAINTENANCE, 'Build-Package.ps1'):
            (source / name).write_text('new maintenance ' + name)
        for name in repack.MAINTENANCE:
            (self.original / name).write_text('old maintenance ' + name)
        (self.original / 'payload/bin/fixed.exe').write_bytes(b'synthetic immutable payload; never executed')
        (self.original / 'payload/package-manifest.json').write_text(json.dumps({'git_commit': repack.RUNTIME_COMMIT}))
        self.rows = repack.inventory(self.original / 'payload')
        self.manifest = dict(format='yime-simple-package-2', product='yimecore', target='windows-arm64',
            host_architecture='arm64', tsf64_architecture='arm64x', version='old',
            files=[dict(path=name, **row) for name, row in self.rows.items()])
        (self.original / 'product-package.json').write_text(json.dumps(self.manifest))
        self.archive = self.root / 'original.zip'
        with zipfile.ZipFile(self.archive, 'x') as zipped:
            for name in repack.inventory(self.original):
                zipped.write(self.original / name, repack.RUNTIME_PREFIX + name)
        anchor = repack.digest(self.archive)
        for key, value in [('PAYLOAD_COUNT', 2), ('RUNTIME_ARCHIVE_SHA256', anchor['sha256']), ('RUNTIME_ARCHIVE_BYTES', anchor['bytes'])]:
            patch = mock.patch.object(repack, key, value); patch.start(); self.addCleanup(patch.stop)
        self.commit = 'b' * 40

    def fake_builder(self, command, **kwargs):
        self.assertIn('--edition', command)
        self.assertEqual(command[command.index('--edition') + 1], 'ps7')
        self.assertTrue(command[command.index('--script') + 1].endswith('Build-Package.ps1'))
        self.assertTrue(command[1].endswith('tools/powershell/run_checked.py') or command[1].endswith('tools\\powershell\\run_checked.py'))
        params = json.loads(Path(command[-1]).read_text())
        self.assertEqual((params['Product'], params['Target'], params['Version']), ('yimecore', 'windows-arm64', repack.VERSION))
        self.assertNotIn('Action', params)
        package = Path(params['OutputRoot']); package.mkdir()
        shutil.copytree(params['PayloadRoot'], package / 'payload')
        manifest = dict(self.manifest, version=repack.VERSION)
        (package / 'product-package.json').write_text(json.dumps(manifest))
        for name in repack.MAINTENANCE:
            shutil.copyfile(self.repo / 'installer/simple' / name, package / name)
        return subprocess.CompletedProcess(command, 0, 'synthetic Build-Package/Read-Package fixture\n', '')

    def build(self, runner=None):
        state = {'commit': self.commit, 'clean': True, 'statusSHA256': '0' * 64}
        with mock.patch.object(repack, 'source_state', return_value=state):
            return repack.build(self.repo, self.original, self.archive, self.root / 'output', self.commit,
                'unused-git', runner=runner or self.fake_builder)

    def test_archive_pin_and_payload_are_both_verified(self):
        self.assertEqual(repack.verify_runtime(self.original, self.archive), self.rows)
        (self.original / 'payload/bin/fixed.exe').write_bytes(b'changed runtime')
        with self.assertRaises(ValueError):
            repack.verify_runtime(self.original, self.archive)

    def test_wrong_archive_fails_before_builder_or_output(self):
        with self.archive.open('ab') as stream:
            stream.write(b'changed archive')
        runner = mock.Mock()
        with self.assertRaises(ValueError):
            self.build(runner)
        runner.assert_not_called()
        self.assertFalse((self.root / 'output').exists())

    def test_success_preserves_payload_and_records_two_sources(self):
        before = repack.inventory(self.original)
        receipt = self.build()
        self.assertEqual(receipt['runtimeSourceCommit'], repack.RUNTIME_COMMIT)
        self.assertEqual(receipt['installerSourceCommit'], self.commit)
        self.assertNotEqual(receipt['runtimeSourceCommit'], receipt['installerSourceCommit'])
        self.assertEqual(receipt['runtimePayloadCount'], 2)
        self.assertFalse(receipt['installationExecuted'])
        self.assertFalse(receipt['sourceCICheckedByTool'])
        self.assertEqual(set(receipt['installerFiles']), {*repack.MAINTENANCE, 'Build-Package.ps1'})
        self.assertEqual(repack.inventory(self.original), before)
        self.assertEqual(repack.inventory(self.root / 'output/package/payload'), self.rows)
        repack.verify_zip(self.root / 'output' / receipt['zip']['name'], receipt['files'])

    def test_builder_cannot_substitute_runtime_or_add_members(self):
        def mutate(*args, **kwargs):
            result = self.fake_builder(*args, **kwargs)
            (self.root / 'output/package/payload/bin/fixed.exe').write_bytes(b'wrong runtime')
            return result
        with self.assertRaisesRegex(ValueError, 'changed pinned runtime'):
            self.build(mutate)
        self.assertFalse(list((self.root / 'output').glob('*.zip')))

    def test_unlisted_original_package_file_rejected(self):
        (self.original / 'unexpected.exe').write_bytes(b'not part of pinned release')
        with self.assertRaises(ValueError):
            repack.verify_runtime(self.original, self.archive)

    def test_formal_source_requires_matching_clean_HEAD(self):
        for head, status, draft, accepted in [(self.commit, '', False, True), (self.commit, ' M file', False, False),
                (self.commit, ' M file', True, True), ('c' * 40, '', True, False)]:
            with self.subTest(head=head, dirty=bool(status), draft=draft), mock.patch.object(
                    repack.subprocess, 'check_output', side_effect=[head + '\n', status]):
                if accepted:
                    self.assertEqual(repack.source_state(self.repo, self.commit, draft, 'git')['clean'], not bool(status))
                else:
                    with self.assertRaises(ValueError):
                        repack.source_state(self.repo, self.commit, draft, 'git')


if __name__ == '__main__':
    unittest.main()
