"""Preparation report rejection paths; no installed payload or Windows mutation."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('preparation', Path(__file__).with_name('prepare_msi_18u_test6.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / 'install'
        self.root.mkdir()
        self.manifest = {'sourceCommit': p.SOURCE, 'product': 'yimecore-18u',
                         'architecture': 'native-x64', 'identity': {'clsid': p.CLSID, 'profile': p.PROFILE},
                         'files': []}
        for i in range(15):
            name = str(i) + '.bin'
            raw = ('synthetic-' + name).encode()
            (self.root / name).write_bytes(raw)
            self.manifest['files'].append({'path': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        (self.root / '.yime-product.json').write_text(json.dumps({
            'format': 'yime-simple-install-1', 'product': 'yimecore-18u',
            'target': 'windows-amd64', 'version': p.VERSION}), encoding='utf-8')
        self.pin_manifest()
        self.observer = Mock(return_value={'digitizerReadyReported': True})

    def pin_manifest(self):
        path = self.root / 'installed-18u-product.json'
        path.write_text(json.dumps(self.manifest), encoding='utf-8')
        patched = patch.object(p, 'DESCRIPTOR_SHA256', p.digest(path))
        patched.start()
        self.addCleanup(patched.stop)

    def test_verified_baseline_never_claims_app_or_physical_readiness(self):
        report = p.assess(self.root, p.HOST, self.observer)
        self.assertTrue(report['baselineVerified'])
        for name in ('readyForInstalledTouchAppTest', 'physicalAcceptancePerformed',
                     'appInputPerformed', 'systemMutationPerformed', 'installedHostRetested'):
            self.assertFalse(report[name])
        self.assertEqual(len(report['blockers']), 2)

    def test_wrong_host_does_not_observe_or_reuse_other_machine_result(self):
        report = p.assess(self.root, 'MYCOMPUTER', self.observer)
        self.assertFalse(report['baselineVerified'])
        self.observer.assert_not_called()

    def test_modified_payload_stops_before_environment_query(self):
        (self.root / '1.bin').write_bytes(b'changed')
        report = p.assess(self.root, p.HOST, self.observer)
        self.assertIn('payload mismatch', report['error'])
        self.observer.assert_not_called()

    def test_untrusted_descriptor_is_rejected(self):
        path = self.root / 'installed-18u-product.json'
        path.write_text('{}', encoding='utf-8')
        self.assertIn('descriptor differs', p.assess(self.root, p.HOST, self.observer)['error'])

    def test_marker_cannot_relabel_other_version(self):
        (self.root / '.yime-product.json').write_text('{}', encoding='utf-8')
        self.assertIn('marker mismatch', p.assess(self.root, p.HOST, self.observer)['error'])

    def test_path_escape_and_case_duplicate_rejected(self):
        for name in ('../outside', 'C:/outside', '1.BIN'):
            with self.subTest(name=name):
                if name == '1.BIN':
                    self.manifest['files'][0] = dict(self.manifest['files'][1])
                    self.manifest['files'][1]['path'] = name
                else:
                    self.manifest['files'][0]['path'] = name
                self.pin_manifest()
                self.assertIn('invalid or duplicate', p.assess(self.root, p.HOST, self.observer)['error'])

    def test_access_denied_remains_inconclusive(self):
        self.observer.side_effect = PermissionError('registration access denied')
        report = p.assess(self.root, p.HOST, self.observer)
        self.assertFalse(report['baselineVerified'])
        self.assertIn('access denied', report['error'])

    def test_missing_digitizer_adds_blocker_not_fake_physical_result(self):
        self.observer.return_value = {'digitizerReadyReported': False}
        report = p.assess(self.root, p.HOST, self.observer)
        self.assertTrue(report['baselineVerified'])
        self.assertEqual(len(report['blockers']), 3)
        self.assertFalse(report['physicalAcceptancePerformed'])

    def test_existing_report_and_install_output_are_preserved(self):
        output = self.base / 'evidence.json'
        output.write_text('original', encoding='utf-8')
        with self.assertRaises(FileExistsError):
            p.write_report(output, self.root, {})
        self.assertEqual(output.read_text(), 'original')
        with self.assertRaisesRegex(ValueError, 'outside installation'):
            p.write_report(self.root / 'new.json', self.root, {})
        self.assertFalse((self.root / 'new.json').exists())


if __name__ == '__main__':
    unittest.main()
