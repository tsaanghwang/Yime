"""Synthetic PE/resource fixtures only; never execute a Windows binary."""
import json
from pathlib import Path
import struct
import stat
import os
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_activated_loop_package as b


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bins = self.root / 'bins'; self.bins.mkdir()
        self.data = self.root / 'data'; self.data.mkdir()
        self.source = self.root / 'source'; self.source.mkdir()
        self.sha = 'a' * 40
        for name in b.BINARIES:
            raw = bytearray(256)
            if name in b.PE_NAMES:
                raw[:2] = b'MZ'; struct.pack_into('<I', raw, 60, 64)
                raw[64:68] = b'PE\0\0'; struct.pack_into('<H', raw, 68, 0x8664)
                struct.pack_into('<H', raw, 86, 2 | (0x2000 if name.endswith('.dll') else 0))
                struct.pack_into('<H', raw, 88, 0x20b)
            (self.bins / name).write_bytes(raw)
        for name in b.SOURCES:
            path = self.source / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('{}')
        for name in b.DATA: (self.data / name).write_text('synthetic-' + name)
        dictionary_sha = b.digest(self.data / 'yime_variable.dict.yaml')['sha256']
        self.addCleanup(patch.stopall); patch.object(b, 'DICTIONARY_SHA', dictionary_sha).start()
        product = {'schema_version': 'yimecore-18u-touch-product-v1', 'installable': False,
                   'identity': {'product_key': 'YimeCore18uTouch', 'clsid': '{6DFACE1F-562E-4773-A9D6-D5753A314711}', 'profile': '{1BD904AC-3194-4419-B70A-5574100F18B3}', 'language_id': '0804'},
                   'scope': {'architecture': 'x64', 'language': 'CN', 'mode': 'variable', 'persistent_learning': False, 'registration_validated': False, 'user_machine_execution_approved': False},
                   'data': {'layout_sha256': b.LAYOUT_SHA, 'dictionary_sha256': dictionary_sha, 'standard_index_fallback': False}}
        self.product = self.source / 'tools/yimecore/18u-touch-product.json'
        self.product.write_text(json.dumps(product))
        self.lock = self.source / 'prototypes/touch-terminal/desktop/resources.lock.json'
        self.lock.parent.mkdir(parents=True); self.lock.write_text(json.dumps({'schemaVersion': 1, 'files': {name: b.digest(self.data/name) for name in b.DATA}}))
        self.extra = {}
        for name in ['runner', 'prepare', 'readme']:
            self.extra[name] = self.root / (name + '.txt'); self.extra[name].write_text('synthetic ' + name)
        self.signatures = self.root / 'signatures.json'
        self.rows = [{'path': 'bin/' + name, **b.digest(self.bins/name), 'status': 'NotSigned', 'signerThumbprint': None} for name in sorted(b.PE_NAMES)]
        self.write_signatures()
        self.output = self.root / 'package.zip'

    def write_signatures(self):
        self.signatures.write_text(json.dumps({'schema': 'activated-loop-signatures-v1', 'sourceCommit': self.sha, 'files': self.rows}))

    def build(self):
        return b.build(self.bins, self.source, self.data, **self.extra, signatures=self.signatures, output=self.output, source_commit=self.sha)

    def test_exact_archive_and_per_file_hashes(self):
        value = self.build()
        self.assertFalse(value['registrationExecuted']); self.assertEqual(value['baseImplementation'], b.BASE)
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), b.PAYLOAD | {'manifest.json'})
            self.assertEqual(len(archive.namelist()), 20)
            for name, row in value['files'].items():
                raw = archive.read(name)
                self.assertEqual(row, {'bytes': len(raw), 'sha256': b.hashlib.sha256(raw).hexdigest()})
            self.assertEqual(json.loads(archive.read('manifest.json')), value)

    def test_actual_prepare_validator_accepts_built_archive(self):
        import prepare_activated_loop_package as entry
        manifest = self.build()
        package = self.root/'unpacked'
        with zipfile.ZipFile(self.output) as archive: archive.extractall(package)
        anchor = b.digest(package/'manifest.json')['sha256']
        actual, parsed, development = entry.validate(package, anchor)
        self.assertEqual(parsed, manifest)
        self.assertEqual(set(development['binaries']), b.BINARIES)
        self.assertEqual(set(development['sources']), b.SOURCES)
        self.assertEqual(set(development['data']), b.DATA)
        self.assertEqual(Path(development['binaryDirectory']), actual/'bin')

    def test_reject_extra_binary_and_data(self):
        for directory in [self.bins, self.data]:
            path = directory/'extra'; path.write_text('x')
            with self.assertRaises(ValueError): self.build()
            path.unlink()

    def test_reject_resource_tampering_and_product_mix(self):
        path = self.data/'yime_full.dict.yaml'; old = path.read_bytes(); path.write_bytes(old+b'x')
        with self.assertRaisesRegex(ValueError, 'locked-resource'): self.build()
        path.write_bytes(old)
        self.product.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'product-descriptor'): self.build()

    def test_reject_pe_architecture_and_dll_kind(self):
        path = self.bins/'YimeTextService18u.dll'; original = path.read_bytes()
        for offset, value in [(68, 0xaa64), (86, 2), (88, 0x10b)]:
            raw = bytearray(original); struct.pack_into('<H', raw, offset, value); path.write_bytes(raw)
            with self.assertRaises(ValueError): self.build()
        path.write_bytes(original)

    def test_reject_stale_signature_hash_duplicate_or_wrong_source(self):
        original = [dict(x) for x in self.rows]
        for mutation in ['hash', 'duplicate', 'source']:
            self.rows = [dict(x) for x in original]
            if mutation == 'hash': self.rows[0]['sha256'] = '0'*64
            if mutation == 'duplicate': self.rows[0] = self.rows[1]
            self.write_signatures()
            if mutation == 'source':
                value = json.loads(self.signatures.read_text()); value['sourceCommit'] = 'b'*40; self.signatures.write_text(json.dumps(value))
            with self.assertRaises(ValueError): self.build()

    def test_no_invented_valid_signer(self):
        self.rows[0]['status'] = 'Valid'; self.write_signatures()
        with self.assertRaisesRegex(ValueError, 'needs-signer'): self.build()
        self.rows[0]['signerThumbprint'] = 'a'*40; self.write_signatures()
        self.build()

    def test_fresh_output_and_symlink_required(self):
        self.output.write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'fresh-output'): self.build()
        self.assertEqual(self.output.read_text(), 'preserve'); self.output.unlink()
        path = self.data/'yime_full.dict.yaml'; target = self.root/'moved'; path.rename(target)
        # Avoid requiring Windows symlink privileges in this offline test.
        original_lstat = Path.lstat
        def simulated_link(candidate, *args, **kwargs):
            if candidate == path:
                values = list(original_lstat(target)); values[0] = stat.S_IFLNK | 0o777
                return os.stat_result(values)
            return original_lstat(candidate, *args, **kwargs)
        path.write_bytes(target.read_bytes())
        with patch.object(Path, 'lstat', simulated_link), self.assertRaisesRegex(ValueError, 'reparse'):
            self.build()

    def test_copy_change_rejected(self):
        original = b.shutil.copyfile
        def change(source, target):
            original(source, target); Path(target).write_bytes(Path(target).read_bytes()+b'x')
        with patch.object(b.shutil, 'copyfile', change), self.assertRaisesRegex(ValueError, 'changed-during-copy'):
            self.build()
        self.assertFalse(self.output.exists())


if __name__ == '__main__': unittest.main()
