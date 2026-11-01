"""Synthetic package and mocked process tests; no Windows probe is executed."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import collect_mycomputer_preflight as collector


def fake_pe(dll):
    data = bytearray(88)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 64)
    data[64:68] = b'PE\0\0'
    struct.pack_into('<H', data, 68, 0x8664)
    struct.pack_into('<H', data, 86, 2 | (0x2000 if dll else 0))
    return data


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / 'package'
        self.package.mkdir()
        for name in collector.PAYLOAD:
            data = fake_pe(name == collector.DLL) if name in (collector.EXE, collector.DLL) else b'# synthetic fixture\n'
            (self.package / name).write_bytes(data)
        self.manifest = dict(schema=collector.SCHEMA, identity=dict(collector.IDENTITY), architecture='native-x64',
                             scope='registration-activation-only-development', targetHost='MyComputer',
                             defaultOperation='read-only-preflight', sourceCommit='a' * 40,
                             userDesktopExecutionApproved=False, registrationExecutionApproved=False,
                             brokerEditingVerified=False, physicalAcceptance=False)
        self.pin()
        self.location = patch.object(collector, '__file__', str(self.package / 'collect_mycomputer_preflight.py'))
        self.location.start()
        self.addCleanup(self.location.stop)
        self.calls = []

    def pin(self):
        self.manifest['files'] = [dict(path=n, sha256=collector.digest(self.package / n), bytes=(self.package / n).stat().st_size) for n in sorted(collector.PAYLOAD)]
        (self.package / collector.MANIFEST).write_text(json.dumps(self.manifest), encoding='utf-8')
        self.sha = collector.digest(self.package / collector.MANIFEST)

    def runner(self, command, cwd, stdout, stderr, timeout):
        self.calls.append((command, cwd, timeout))
        stdout.write_bytes(b'{"status":"preflight-only"}\n')
        stderr.write_bytes(b'')
        return dict(started=True, treeStopped=True, timedOut=False, errorCode=None, exitCode=0)

    def collect(self, **kwargs):
        return collector.collect(self.package, self.root / 'evidence', self.sha, runner=kwargs.pop('runner', self.runner), **kwargs)

    def test_single_exact_preflight_and_same_run_evidence(self):
        receipt = self.collect()
        self.assertEqual(len(self.calls), 1)
        command, cwd, timeout = self.calls[0]
        # Windows TEMP may use an 8.3 alias; production deliberately resolves it.
        package = self.package.resolve(strict=True)
        self.assertEqual(command, [str(package / collector.EXE), '--preflight', '--dll', str(package / collector.DLL), '--sha256', collector.digest(package / collector.DLL)])
        self.assertEqual(cwd, (self.root / 'evidence').resolve(strict=True))
        self.assertEqual(timeout, 30)
        self.assertEqual(receipt['status'], 'collected')
        self.assertFalse(receipt['noWritesProven'])
        self.assertEqual(receipt['stdout']['sha256'], collector.digest(cwd / 'stdout.txt'))
        self.assertEqual(json.loads((cwd / 'collection.json').read_text()), receipt)

    def test_timeout_is_not_success_or_no_write_proof(self):
        def timeout(*args):
            result = self.runner(*args)
            result.update(timedOut=True, exitCode=124)
            return result
        receipt = self.collect(runner=timeout)
        self.assertEqual(receipt['status'], 'failed-or-inconclusive')
        self.assertFalse(receipt['noWritesProven'])
        self.assertEqual(len(self.calls), 1)

    def test_tree_unknown_and_nonzero_never_pass(self):
        for change in ({'treeStopped': False}, {'exitCode': 3}, {'errorCode': 5}, {'started': False}):
            with self.subTest(change=change):
                out = self.root / ('evidence-' + next(iter(change)))
                def runner(*args):
                    result = self.runner(*args)
                    result.update(change)
                    return result
                receipt = collector.collect(self.package, out, self.sha, runner=runner)
                self.assertEqual(receipt['status'], 'failed-or-inconclusive')

    def test_tampered_payload_stops_before_runner(self):
        (self.package / collector.EXE).write_bytes(b'changed')
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)
        self.assertFalse((self.root / 'evidence').exists())

    def test_independent_manifest_anchor_required(self):
        self.manifest['sourceCommit'] = 'b' * 40
        old_sha = self.sha
        self.pin()
        with self.assertRaises(ValueError):
            collector.collect(self.package, self.root / 'evidence', old_sha, runner=self.runner)
        self.assertFalse(self.calls)

    def test_extra_file_refused(self):
        (self.package / 'unreviewed.dll').write_bytes(b'')
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)

    def test_v2_missing_companions_and_v1_extra_companions_rejected(self):
        self.manifest['schema'] = collector.SCHEMA_V2
        self.pin()
        with self.assertRaises(ValueError): self.collect()
        self.manifest['schema'] = collector.SCHEMA
        (self.package / 'run_mycomputer_registration.py').write_text('# not a v1 payload')
        self.pin()
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)

    def test_wrong_product_identity_refused(self):
        self.manifest['identity']['clsid'] = '00000000-0000-0000-0000-000000000000'
        self.pin()
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)

    def test_wrong_pe_identity_refused_even_when_manifest_pinned(self):
        (self.package / collector.EXE).write_bytes(fake_pe(True))
        self.pin()
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)

    def test_existing_evidence_never_overwritten(self):
        evidence = self.root / 'evidence'
        evidence.mkdir()
        (evidence / 'retain').write_text('original')
        with self.assertRaises(FileExistsError): self.collect()
        self.assertEqual((evidence / 'retain').read_text(), 'original')
        self.assertFalse(self.calls)

    def test_evidence_parent_alias_into_package_refused(self):
        alias = self.root / 'package-alias'
        try:
            alias.symlink_to(self.package, target_is_directory=True)
        except OSError:
            # Windows without symlink privilege: exercise the resolved-ancestor
            # boundary with a resolver mock instead of skipping the contract.
            original = Path.resolve
            def resolve(path, strict=False):
                if path == alias / 'new-evidence':
                    return self.package / 'new-evidence'
                return original(path, strict=strict)
            with patch.object(Path, 'resolve', resolve):
                with self.assertRaises(ValueError):
                    collector.collect(self.package, alias / 'new-evidence', self.sha, runner=self.runner)
            self.assertFalse(self.calls)
            return
        with self.assertRaises(ValueError):
            collector.collect(self.package, alias / 'new-evidence', self.sha, runner=self.runner)
        self.assertFalse((self.package / 'new-evidence').exists())
        self.assertFalse(self.calls)

    def test_bad_deadline_refused(self):
        for value in (0, 121, True):
            with self.assertRaises(ValueError): self.collect(timeout=value)
        self.assertFalse(self.calls)

    def test_launch_failure_retains_receipt_without_success(self):
        def failed(*args): raise OSError('synthetic')
        receipt = self.collect(runner=failed)
        self.assertEqual(receipt['status'], 'launch-error-or-inconclusive')
        self.assertIsNone(receipt['process'])
        self.assertIsNotNone(receipt['completedUtc'])

    def test_manifest_path_escape_refused(self):
        self.manifest['files'][0]['path'] = '../escape.dll'
        (self.package / collector.MANIFEST).write_text(json.dumps(self.manifest))
        self.sha = collector.digest(self.package / collector.MANIFEST)
        with self.assertRaises(ValueError): self.collect()
        self.assertFalse(self.calls)


if __name__ == '__main__': unittest.main()
