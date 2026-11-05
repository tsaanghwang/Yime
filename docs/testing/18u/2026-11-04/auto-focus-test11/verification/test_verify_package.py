"""Synthetic verifier tests only: mock PE bytes are never executed."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

SCRIPT = Path(__file__).with_name('verify_package.py')
spec = importlib.util.spec_from_file_location('verify_package', SCRIPT)
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
SOURCE = 'f' * 40


def encoded(value):
    return (json.dumps(value, sort_keys=True) + '\n').encode()


def archive_bytes(files):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, raw in files.items():
            archive.writestr(name, raw)
    return stream.getvalue()


def corrupt_stored_member(raw, member):
    data = bytearray(raw)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        info = archive.getinfo(member)
        offset = info.header_offset
        name_size, extra_size = struct.unpack_from('<HH', data, offset + 26)
        data[offset + 30 + name_size + extra_size] ^= 1
    return bytes(data)


class VerifierTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='synthetic-', dir=SCRIPT.parent)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = {n: ('synthetic data ' + n).encode() for n in v.DATA}
        expected = {n: v.digest_bytes(raw) for n, raw in self.data.items()}
        self.lock = encoded({'schemaVersion': 1, 'layoutProjectionSHA256': v.LAYOUT_SHA,
                             'archiveSHA256': v.ARCHIVE_SHA, 'files': expected})
        self.addCleanup(patch.stopall)
        patch.object(v, 'DATA', expected).start()
        patch.object(v, 'LOCK_SHA', v.digest_bytes(self.lock)['sha256']).start()

    def fixture(self, *, v1=False, wrong_arch=False, dirty=False, missing_asset=False):
        pe = bytearray(128)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 60, 64)
        pe[64:68] = b'PE\0\0'
        struct.pack_into('<H', pe, 68, 0xAA64 if wrong_arch else 0x8664)
        struct.pack_into('<H', pe, 88, 0x20B)
        files = {n: bytes(pe) for n in v.PE_FILES}
        for name, encoding in ((v.FRONT + 'YimeTouchKeyboard.exe', 'ascii'),
                               ('payload/x64/YimeTextService18u.dll', 'utf-16-le')):
            files[name] += v.PROTOCOL['pipePrefix'].encode(encoding)
        if v1:
            files[v.FRONT + 'YimeTouchKeyboard.exe'] += b'Yime18u.Frontend.v1.'
        for name in v.SOURCE_RESOURCES:
            files['payload/' + name] = b'synthetic resource'
        files['payload/source/prototypes/touch-terminal/desktop/resources.lock.json'] = self.lock
        files['payload/source/tools/yimecore/18u-touch-product.json'] = encoded({
            'identity': v.IDENTITY,
            'data': {'layout_sha256': v.LAYOUT_SHA, 'dictionary_sha256': v.DATA['yime_variable.dict.yaml']['sha256'],
                     'standard_index_fallback': False}})
        files['payload/source/prototypes/touch-terminal/data/physical-layout.json'] = encoded({'layoutId': v.LAYOUT_SHA})
        files['payload/source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'] = encoded({'synthetic': 'projection'})
        for name in v.FRONTEND_FIXED - {'YimeTouchKeyboard.exe', 'manifest.json', 'resources.json'}:
            files[v.FRONT + name] = b'synthetic frontend resource; never execute'
        files[v.FRONT + 'resources.lock.json'] = self.lock
        for name in ('prototypes/touch-terminal/data/physical-layout.json', 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'):
            files[v.FRONT + name] = files['payload/source/' + name]
        for name, raw in self.data.items():
            files['payload/data/' + name] = raw
            files[v.FRONT + 'data/' + name] = raw
        if missing_asset:
            del files[v.FRONT + 'Start Local Preview.cmd']
        front_files = lambda: {n[len(v.FRONT):]: v.digest_bytes(raw)['sha256'] for n, raw in files.items() if n.startswith(v.FRONT)}
        resources = {'schemaVersion': 1, 'scope': 'isolated-cn134-portable-resources', 'sourceCommit': SOURCE,
                     'sourceChanges': False, 'architecture': 'windows-amd64',
                     'files': {n: sha for n, sha in front_files().items() if n != 'YimeTouchKeyboard.exe'}}
        files[v.FRONT + 'resources.json'] = encoded(resources)
        frontend = {'schemaVersion': 2, 'scope': 'installed-18u-tsf-frontend-candidate',
                    'sourceCommit': SOURCE, 'sourceChanges': dirty, 'architecture': 'windows-amd64',
                    'sendInputFallback': False, 'defaultMode': 'installed-tsf-auto-focus',
                    'defaultLauncher': 'Start Installed Touch Keyboard.cmd', 'completeChineseResources': True,
                    'frontendProtocol': v.PROTOCOL, 'hardwareAcceptance': False, 'installedProductAcceptance': False,
                    'arm64NativeAcceptance': False, 'resourceArchiveSHA256': v.ARCHIVE_SHA,
                    'portableResourcesSHA256': v.digest_bytes(files[v.FRONT + 'resources.json'])['sha256'],
                    'files': front_files()}
        files[v.FRONT + 'manifest.json'] = encoded(frontend)
        payload_rows = lambda: [dict(path=n[len('payload/'):], **v.digest_bytes(raw)) for n, raw in files.items() if n.startswith('payload/')]
        files['payload/installed-18u-product.json'] = encoded({
            'schema': 'installed-18u-product-v1', 'product': 'yimecore-18u', 'sourceCommit': SOURCE,
            'identity': v.IDENTITY, 'architecture': 'native-x64', 'language': 'CN', 'mode': 'variable',
            'autostart': False, 'files': payload_rows()})
        files['product-package.json'] = encoded({'format': 'yime-simple-package-18u-1', 'product': 'yimecore-18u',
            'version': v.VERSION, 'target': 'windows-amd64', 'host_architecture': 'amd64', 'tsf64_architecture': 'x64',
            'files': payload_rows()})
        files['signatures.json'] = encoded({'schema': 'installed-18u-signatures-v1', 'sourceCommit': SOURCE,
            'files': [dict(path=n, **v.digest_bytes(files[n]), status='NotSigned', signerThumbprint=None) for n in sorted(v.PE_FILES)]})
        for name in v.INSTALLER_FILES | {'README.zh-CN.md'}:
            files[name] = b'synthetic installer text; never execute'
        files['package-evidence.json'] = encoded({'schema': 'installed-18u-package-evidence-v1',
            'sourceCommit': SOURCE, 'version': v.VERSION, 'product': 'yimecore-18u', 'architecture': 'native-x64',
            'installationExecuted': False, 'registrationExecuted': False, 'installedHostAcceptance': False,
            'frontendProtocol': v.PROTOCOL, 'files': {n: v.digest_bytes(raw) for n, raw in files.items()}})
        return files

    def inputs(self, files=None, *, inner=None, outer=None, api_digest=True):
        if files is None:
            files = self.fixture()
        if inner is None:
            inner = archive_bytes(files)
        if outer is None:
            outer = archive_bytes({v.ZIP_NAME: inner})
        receipt = {'sourceCommit': SOURCE, 'zip': v.ZIP_NAME, **v.digest_bytes(inner),
                   'packageEvidence': v.digest_bytes(files['package-evidence.json']),
                   'installedDescriptor': v.digest_bytes(files['payload/installed-18u-product.json']),
                   'frontendProtocol': v.PROTOCOL}
        metadata = {'id': 123, 'name': 'installed-18u-x64-test-package-' + SOURCE, 'expired': False,
                    'size_in_bytes': len(outer), 'workflow_run': {'id': 456, 'head_sha': SOURCE},
                    'digest': 'sha256:' + v.digest_bytes(outer)['sha256'] if api_digest else None}
        for name, raw in [('outer.zip', outer), ('receipt.json', encoded(receipt)), ('artifact.json', encoded(metadata))]:
            (self.root / name).write_bytes(raw)
        return argparse.Namespace(artifact_zip=self.root / 'outer.zip', artifact_metadata=self.root / 'artifact.json',
                                  ci_receipt=self.root / 'receipt.json', source_commit=SOURCE, output=self.root / 'verified')

    def test_complete_synthetic_archive_only(self):
        args = self.inputs()
        path = v.verify(args)
        report = json.loads(path.read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['innerArchive']['fileCount'], 46)
        self.assertEqual(len(report['innerArchive']['peFiles']), 6)
        self.assertTrue(report['outerArchive']['apiDigestVerified'])
        self.assertTrue(all(report[k] is False for k in v.NO_ACTIONS))
        self.assertEqual({p.name for p in args.output.iterdir()}, {v.ZIP_NAME, 'evidence', 'download-verification.json'})
        self.assertFalse((args.output / 'payload').exists())
        self.assertEqual((args.output / 'evidence/package-evidence.json').read_bytes(), self.fixture()['package-evidence.json'])

    def test_no_overwrite(self):
        args = self.inputs()
        args.output.mkdir()
        sentinel = args.output / 'keep'
        sentinel.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'no overwrite'):
            v.verify(args)
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_optional_api_digest_recorded_absent(self):
        args = self.inputs(api_digest=False)
        report = json.loads(v.verify(args).read_text())
        self.assertFalse(report['outerArchive']['apiDigestVerified'])

    def test_metadata_digest_and_source_rejected(self):
        for field, bad in [('digest', 'sha256:' + '0' * 64), ('workflow_run', {'id': 456, 'head_sha': 'e' * 40})]:
            with self.subTest(field=field):
                args = self.inputs()
                args.output = self.root / field
                metadata = json.loads(args.artifact_metadata.read_text())
                metadata[field] = bad
                args.artifact_metadata.write_bytes(encoded(metadata))
                with self.assertRaises(ValueError):
                    v.verify(args)
                self.assertEqual(json.loads((args.output / 'download-verification.json').read_text())['status'], 'failed')

    def test_self_consistent_v1_wrong_arch_dirty_and_missing_asset_rejected(self):
        for option in ('v1', 'wrong_arch', 'dirty', 'missing_asset'):
            with self.subTest(option=option):
                args = self.inputs(self.fixture(**{option: True}))
                args.output = self.root / option
                with self.assertRaises(ValueError):
                    v.verify(args)

    def test_manifest_hash_mismatch_rejected(self):
        files = self.fixture()
        files['Setup.cmd'] = b'changed after evidence'
        with self.assertRaisesRegex(ValueError, 'inventory/hash mismatch'):
            v.verify(self.inputs(files))

    def test_receipt_version_mismatch_rejected(self):
        args = self.inputs()
        receipt = json.loads(args.ci_receipt.read_text())
        receipt['zip'] = v.ZIP_NAME.replace('test.11', 'test.10')
        args.ci_receipt.write_bytes(encoded(receipt))
        with self.assertRaisesRegex(ValueError, 'source/version'):
            v.verify(args)

    def test_inner_and_outer_crc_rejected(self):
        files = self.fixture()
        inner = archive_bytes(files)
        for layer in ('inner', 'outer'):
            with self.subTest(layer=layer):
                if layer == 'inner':
                    args = self.inputs(files, inner=corrupt_stored_member(inner, 'Setup.cmd'))
                else:
                    args = self.inputs(files, outer=corrupt_stored_member(archive_bytes({v.ZIP_NAME: inner}), v.ZIP_NAME))
                args.output = self.root / layer
                with self.assertRaises(zipfile.BadZipFile):
                    v.verify(args)

    def test_unsafe_members_rejected_before_extraction(self):
        for name in ('../x', '/x', 'C:/x', 'a/../b', 'a//b', './a', 'a.', 'x /b', 'NUL.txt', 'a:x'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                with zipfile.ZipFile(io.BytesIO(archive_bytes({name: b'x'}))) as archive:
                    v.members(archive)
        # ZipInfo creation normalizes backslashes on Windows; put the unsafe
        # bytes into both stored filename headers to exercise incoming ZIPs.
        raw = archive_bytes({'a/b': b'x'}).replace(b'a/b', b'a\\b')
        with zipfile.ZipFile(io.BytesIO(raw)) as archive, self.assertRaises(ValueError):
            v.members(archive)

    def test_duplicates_case_alias_and_collision_rejected(self):
        for names in [('x', 'x'), ('x', 'X'), ('a', 'a/b')]:
            stream = io.BytesIO()
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(stream, 'w') as archive:
                    for name in names:
                        archive.writestr(name, b'x')
            with self.subTest(names=names), self.assertRaises(ValueError):
                with zipfile.ZipFile(stream) as archive:
                    v.members(archive)

    def test_symlink_zip_member_rejected(self):
        stream = io.BytesIO()
        info = zipfile.ZipInfo('linked')
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr(info, '../outside')
        with zipfile.ZipFile(stream) as archive, self.assertRaisesRegex(ValueError, 'linked or special'):
            v.members(archive)

    def test_duplicate_json_members_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON'):
            v.unique_json(b'{"files": {}, "files": {}}')


if __name__ == '__main__':
    unittest.main(verbosity=2)
