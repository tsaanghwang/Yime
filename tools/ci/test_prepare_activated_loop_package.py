"""Synthetic package and fake process tests, never native registration/preflight."""
import copy
import json
from pathlib import Path
import shutil
import struct
import unittest
from unittest.mock import patch, Mock
import prepare_activated_loop_package as entry
import test_run_activated_registration_loop as fixtures


class PackageEntryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.SyntheticLoopTests(); self.fixture.setUp(); self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root; self.package = self.root/'package'; self.package.mkdir()
        for source, target in [(self.fixture.bins, 'bin'), (self.fixture.source, 'source'), (self.fixture.data, 'data')]: shutil.copytree(source, self.package/target)
        for name in entry.ROOT:
            source = Path(entry.__file__).with_name(name)
            (self.package/name).write_bytes(source.read_bytes() if source.is_file() else b'fixture')
        for name in entry.PE:
            payload = bytearray(88); payload[:2] = b'MZ'; struct.pack_into('<I', payload, 60, 64)
            payload[64:68] = b'PE\0\0'; struct.pack_into('<H', payload, 68, 0x8664)
            struct.pack_into('<H', payload, 86, 2 | (0x2000 if name.endswith('.dll') else 0))
            (self.package/name).write_bytes(payload)
        self.signatures = {'schema': 'activated-loop-signatures-v1', 'sourceCommit': 'a'*40, 'files': [dict(path=n, **entry.digest(self.package/n), status='NotSigned', signerThumbprint=None) for n in sorted(entry.PE)]}
        (self.package/'signatures.json').write_text(json.dumps(self.signatures))
        self.manifest = dict(schema='activated-loop-package-v1', sourceCommit='a'*40, baseImplementation=entry.BASE_IMPLEMENTATION, architecture='native-x64', scope='activated-instance-single-edit-development', registrationExecuted=False, userMachineExecutionApproved=False, files={})
        self.repin()
        original_load = entry.load
        self.loader = patch.object(entry, 'load', side_effect=lambda path, name: fixtures.loop if name == 'pinned_activated_loop' else original_load(path, name)); self.loader.start(); self.addCleanup(self.loader.stop)
    def repin(self):
        self.manifest['files'] = {n: entry.digest(self.package/n) for n in entry.FILES}
        (self.package/'manifest.json').write_text(json.dumps(self.manifest)); self.anchor = entry.digest(self.package/'manifest.json')['sha256']
    def prepare(self): return entry.execute(self.package, self.anchor, self.root/'prepared')
    def test_default_is_static_and_development_manifest_matches_original(self):
        runner = Mock(side_effect=AssertionError('no processes'))
        result = entry.execute(self.package, self.anchor, self.root/'prepared', runner=runner)
        self.assertEqual(result['status'], 'prepared-static-only'); runner.assert_not_called()
        data, roots = fixtures.loop.inputs(self.root/'prepared/development-manifest.json', result['developmentManifestSHA256'])
        self.assertEqual(data['sourceCommit'], 'a'*40); self.assertEqual(roots['binaryDirectory'], self.package/'bin')
    def test_hash_and_exact_set_fail_before_import(self):
        (self.package/'unexpected.exe').write_bytes(b'')
        with self.assertRaises(ValueError): self.prepare()
        (self.package/'unexpected.exe').unlink(); (self.package/'README.zh-CN.md').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.prepare()
    def test_manifest_anchor_and_duplicate_fields_rejected(self):
        with self.assertRaises(ValueError): entry.validate(self.package, '0'*64)
        p = self.package/'manifest.json'; p.write_text(p.read_text().replace('"schema":', '"schema":"duplicate","schema":', 1))
        with self.assertRaises(ValueError): entry.validate(self.package, entry.digest(p)['sha256'])
    def test_arm_pe_or_wrong_dll_flag_rejected(self):
        p = self.package/'bin/YimeTextService18u.dll'; raw = bytearray(p.read_bytes()); struct.pack_into('<H', raw, 68, 0xaa64); p.write_bytes(raw); self.repin()
        with self.assertRaisesRegex(ValueError, 'pe-native-amd64'): self.prepare()
    def test_source_and_authority_not_inherited(self):
        for field, value in [('baseImplementation', 'b'*40), ('registrationExecuted', True), ('userMachineExecutionApproved', True)]:
            old = self.manifest[field]; self.manifest[field] = value; self.repin()
            with self.assertRaises(ValueError): self.prepare()
            self.manifest[field] = old
    def test_output_not_in_package_or_existing(self):
        for output in [self.package/'out', self.root]:
            with self.assertRaises(ValueError): entry.execute(self.package, self.anchor, output)
    def test_signature_source_or_payload_mismatch_rejected(self):
        self.signatures['files'][0]['sha256'] = '0'*64
        (self.package/'signatures.json').write_text(json.dumps(self.signatures)); self.repin()
        with self.assertRaisesRegex(ValueError, 'signature-payload-match'): self.prepare()
    def test_signature_malformed_status_and_unsigned_signer_rejected(self):
        for status, thumb in [([], None), ('NotSigned', 'a'*40)]:
            self.signatures['files'][0].update(status=status, signerThumbprint=thumb)
            (self.package/'signatures.json').write_text(json.dumps(self.signatures)); self.repin()
            with self.assertRaises(ValueError): self.prepare()
    def test_register_requires_separate_confirmation(self):
        with self.assertRaises(ValueError): entry.execute(self.package, self.anchor, self.root/'register', mode='register')
        with self.assertRaises(ValueError): entry.execute(self.package, self.anchor, self.root/'prepare', confirm=entry.CONFIRM)
    def test_register_delegates_only_matching_prepared_manifest(self):
        result = self.prepare(); prepared = self.root/'prepared/development-manifest.json'
        with patch.object(fixtures.loop, 'execute', return_value={'status': 'mock-not-real-registration'}) as original:
            entry.execute(self.package, self.anchor, self.root/'register', 'register', prepared, result['developmentManifestSHA256'], entry.CONFIRM)
            self.assertEqual(original.call_count, 1)
            prepared.write_text('{}')
            with self.assertRaises(ValueError): entry.execute(self.package, self.anchor, self.root/'register2', 'register', prepared, entry.digest(prepared)['sha256'], entry.CONFIRM)
            self.assertEqual(original.call_count, 1)
    def test_preflight_false_prerequisites_is_observation_not_registration(self):
        def runner(command, cwd, stdout, stderr, timeout):
            self.assertEqual(command[1], '--preflight'); self.assertNotIn('--register-once', command); self.assertEqual(timeout, 30)
            report = fixtures.verify_fixture(); report.update(mode='preflight', status='checked', cleanupVerified=False, dllSha256=self.manifest['files']['bin/YimeTextService18u.dll']['sha256'])
            report['preconditions'] = {k: False for k in report['preconditions']}
            Path(stdout).write_text(json.dumps(report)); Path(stderr).write_bytes(b'')
            return dict(started=True, treeStopped=True, timedOut=False, errorCode=None, exitCode=0)
        result = entry.execute(self.package, self.anchor, self.root/'observed', 'preflight', runner=runner)
        self.assertEqual(result['status'], 'preflight-observed-not-registration'); self.assertFalse(result['preflight']['prerequisitesSatisfied'])
    def test_preflight_error_stage_code_or_activation_is_incomplete(self):
        for field, value in [('stage', 'query-failed'), ('code', 1), ('actualDllActivationVerified', True)]:
            with self.subTest(field=field):
                def runner(command, cwd, stdout, stderr, timeout):
                    report = fixtures.verify_fixture(); report.update(mode='preflight', status='checked')
                    report[field] = value
                    Path(stdout).write_text(json.dumps(report)); Path(stderr).write_bytes(b'')
                    return dict(started=True, treeStopped=True, timedOut=False, errorCode=None, exitCode=0)
                result = entry.execute(self.package, self.anchor, self.root/field, 'preflight', runner=runner)
                self.assertEqual(result['status'], 'preflight-incomplete')
                self.assertEqual(result['preflight'][field], value)
    def test_cli_fails_closed_for_original_inconclusive_or_wrong_mode_success(self):
        for mode, status in [('register', 'failed-or-inconclusive'), ('register', 'prepared-static-only'), ('preflight', 'edit-and-independent-cleanup-evidence-consistent')]:
            with self.subTest(mode=mode, status=status), patch.object(entry.sys, 'argv', ['entry', '--mode', mode, '--package', str(self.package), '--manifest-sha256', self.anchor, '--output', str(self.root/'unused')]), patch.object(entry, 'execute', return_value={'status': status}), patch('builtins.print'):
                self.assertEqual(entry.main(), 1)
    def test_preflight_timeout_cannot_chain_registration(self):
        runner = Mock(return_value=dict(started=True, treeStopped=False, timedOut=True, errorCode=None, exitCode=None))
        result = entry.execute(self.package, self.anchor, self.root/'timeout', 'preflight', runner=runner)
        self.assertEqual(result['status'], 'preflight-incomplete'); self.assertEqual(runner.call_count, 1)


if __name__ == '__main__': unittest.main()
