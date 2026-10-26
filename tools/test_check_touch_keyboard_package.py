"""Execution-gate regressions; all target process launches are mocked."""
from pathlib import Path
import json
import os
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_touch_keyboard_package as checker


def pe_image(machine):
    data = bytearray(0x80 + 24)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<H', data, 0x84, machine)
    struct.pack_into('<H', data, 0x80 + 22, 0x0002)
    return bytes(data)


def host(architecture, process_machine='0x0000'):
    return {'native_architecture': 'x64' if architecture == 'amd64' else architecture,
            'native_machine': f'0x{checker.PE_MACHINES["windows-"+architecture]:04x}',
            'process_machine': process_machine, 'source': 'IsWow64Process2'}


class NativePackageExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='yime-package-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root/'package'
        self.report = self.root/'evidence'/'check.json'

    def make_package(self, architecture='arm64', machine=None, image=None):
        self.package.mkdir()
        files = {
            'YimeTouchKeyboard.exe': image if image is not None else pe_image(
                checker.PE_MACHINES['windows-'+architecture] if machine is None else machine),
            'resources.json': b'{}',
            'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf': b'font',
            'prototypes/touch-terminal/data/physical-layout.json': b'{}',
            'data/ascii_keyboard_manifest.json': b'{}',
            'data/yime_variable.dict.yaml': b'fixture',
        }
        for name, data in files.items():
            path = self.package/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        manifest = {
            'scope': 'uninstalled-desktop-touch-keyboard-chinese-experiment',
            'completeChineseResources': True, 'architecture': 'windows-'+architecture,
            'sourceCommit': 'fixture-only', 'sourceChanges': False,
            'resourceArchiveSHA256': 'fixture-only', 'arm64NativeAcceptance': False,
            'portableResourcesSHA256': checker.digest(self.package/'resources.json'),
            'files': {name: checker.digest(self.package/name) for name in files},
        }
        (self.package/'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        return {p.relative_to(self.package).as_posix(): p.read_bytes()
                for p in self.package.rglob('*') if p.is_file()}

    def run_diagnostics(self, args, **kwargs):
        # The checker must never request UI or input in its default path.
        self.assertIn('--check-package', args)
        self.assertNotIn('--preview', args)
        self.assertNotIn('--host-input', args)
        self.assertNotIn('--host-self-test', args)
        self.assertNotIn('--self-test', args)
        self.assertEqual(list(kwargs['cwd'].iterdir()), [])
        environment = kwargs['env']
        self.assertNotIn('YIME_TEST_SENTINEL', environment)
        self.assertNotIn('GOFLAGS', environment)
        for name in ('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA'):
            self.assertTrue(Path(environment[name]).is_dir())
            self.assertTrue(Path(environment[name]).is_relative_to(kwargs['cwd'].parent))
        if '--data-report' in args:
            full = '--numeric-zones' in args
            report = {'confirmedChineseInMemory': dict.fromkeys(('variable','full','shorthand'), '你'),
                      'boardWidthU': 24.75 if full else 18, 'keyCount': 134 if full else 100,
                      'hostInputSent': False}
            Path(args[args.index('--data-report')+1]).write_text(json.dumps(report), encoding='utf-8')
            return subprocess.CompletedProcess(args, 0, b'', b'')
        return subprocess.CompletedProcess(args, 1, b'', b'fixture rejection')

    def assert_rejected_before_launch(self, detected_host, pattern):
        with patch.object(checker, 'get_machine_architecture', return_value=detected_host), \
             patch.object(checker.subprocess, 'run') as launch:
            with self.assertRaisesRegex(ValueError, pattern):
                checker.check(self.package, self.report)
            launch.assert_not_called()
        self.assertFalse(self.report.exists())

    def test_arm64_uses_native_api_despite_amd64_environment(self):
        originals = self.make_package()
        detected = host('arm64', process_machine='0x8664')
        with patch.dict(os.environ, {'PROCESSOR_ARCHITECTURE': 'AMD64',
                                   'PROCESSOR_ARCHITEW6432': 'AMD64',
                                   'YIME_TEST_SENTINEL': 'must-not-reach-child',
                                   'GOFLAGS': '-unrelated'}), \
             patch.object(checker, 'get_machine_architecture', return_value=detected), \
             patch.object(checker.subprocess, 'run', side_effect=self.run_diagnostics) as launch:
            checker.check(self.package, self.report)
        self.assertEqual(launch.call_count, 10)
        report = json.loads(self.report.read_text(encoding='utf-8'))
        self.assertEqual(report['hostArchitecture'], detected)
        self.assertEqual(report['nativeExecution']['executableMachine'], '0xaa64')
        self.assertTrue(report['nativeExecution']['targetExecuted'])
        self.assertTrue(report['nativeExecution']['architectureMatched'])
        self.assertFalse(report['hostInputSent'])
        self.assertFalse(report['controlledOwnEDIT'])
        self.assertFalse(report['renderedPreview'])
        self.assertFalse(report['arm64NativeAcceptance'])
        self.assertFalse(report['hardwareAcceptance'])
        self.assertEqual(originals, {p.relative_to(self.package).as_posix(): p.read_bytes()
                                    for p in self.package.rglob('*') if p.is_file()})

    def test_existing_x64_ci_path_remains_supported(self):
        self.make_package('amd64')
        with patch.object(checker, 'get_machine_architecture', return_value=host('amd64')), \
             patch.object(checker.subprocess, 'run', side_effect=self.run_diagnostics):
            checker.check(self.package, self.report)
        report = json.loads(self.report.read_text(encoding='utf-8'))
        self.assertEqual(report['nativeExecution']['executableMachine'], '0x8664')
        self.assertFalse(report['arm64NativeAcceptance'])

    def test_x64_package_is_not_native_arm64_evidence(self):
        self.make_package('amd64')
        self.assert_rejected_before_launch(host('arm64'), 'native Windows host')

    def test_arm64_package_cannot_run_on_x64_host(self):
        self.make_package('arm64')
        self.assert_rejected_before_launch(host('amd64'), 'native Windows host')

    def test_manifest_matching_hash_cannot_hide_wrong_pe_machine(self):
        self.make_package('arm64', machine=0x8664)
        self.assert_rejected_before_launch(host('arm64'), 'PE architecture')

    def test_invalid_pe_is_rejected(self):
        self.make_package(image=b'not a Windows executable')
        self.assert_rejected_before_launch(host('arm64'), 'DOS header')

    def test_native_api_failure_does_not_fall_back_to_environment(self):
        self.make_package('amd64')
        with patch.dict(os.environ, {'PROCESSOR_ARCHITECTURE': 'AMD64'}), \
             patch.object(checker, 'get_machine_architecture', side_effect=OSError('native API unavailable')), \
             patch.object(checker.subprocess, 'run') as launch:
            with self.assertRaisesRegex(OSError, 'native API unavailable'):
                checker.check(self.package, self.report)
            launch.assert_not_called()
        self.assertFalse(self.report.exists())

    def test_unverified_detection_source_is_rejected(self):
        self.make_package()
        detected = host('arm64')
        detected['source'] = 'environment'
        self.assert_rejected_before_launch(detected, 'native Windows host')

    def test_existing_report_is_never_overwritten(self):
        self.make_package()
        self.report.parent.mkdir()
        self.report.write_bytes(b'previous evidence')
        with patch.object(checker.subprocess, 'run') as launch:
            with self.assertRaises(FileExistsError):
                checker.check(self.package, self.report)
            launch.assert_not_called()
        self.assertEqual(self.report.read_bytes(), b'previous evidence')

    def test_report_cannot_modify_original_package(self):
        self.make_package()
        with patch.object(checker.subprocess, 'run') as launch:
            with self.assertRaisesRegex(ValueError, 'outside the original package'):
                checker.check(self.package, self.package/'result.json')
            launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
