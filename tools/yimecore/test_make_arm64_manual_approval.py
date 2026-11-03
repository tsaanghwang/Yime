"""Offline draft-generation tests; no package is installed or executed."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.yimecore.make_arm64_manual_approval import COMMIT, make_draft


class ApprovalDraftTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='yime-arm64-approval-')
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / 'package.zip'
        self.files = {
            'Product.psm1': b'module', 'Setup.ps1': b'setup', 'Setup.cmd': b'cmd',
            'product-package.json': json.dumps({
                'format': 'yime-simple-package-18u-1', 'product': 'yimecore-18u',
                'target': 'windows-arm64', 'host_architecture': 'arm64',
                'tsf64_architecture': 'arm64'}).encode(),
            'payload/installed-18u-product.json': json.dumps({
                'schema': 'installed-18u-product-v1', 'sourceCommit': COMMIT,
                'architecture': 'native-arm64'}).encode(),
        }

    def write(self, extra=None):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            for name, data in {**self.files, **(extra or {})}.items():
                archive.writestr(name, data)
        return hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def test_exact_archive_inventory(self):
        sha = self.write()
        draft = make_draft(self.archive, sha, 'S-1-5-21-100-200-300-400')
        self.assertEqual(draft['archiveSha256'], sha)
        self.assertEqual({r['path'] for r in draft['files']}, set(self.files))

    def test_wrong_independent_hash_refused(self):
        self.write()
        with self.assertRaisesRegex(ValueError, 'independently supplied'):
            make_draft(self.archive, '0' * 64, 'S-1-5-21-100-200-300-400')

    def test_zip_traversal_refused(self):
        sha = self.write({'../Setup.ps1': b'bad'})
        with self.assertRaisesRegex(ValueError, 'unsafe'):
            make_draft(self.archive, sha, 'S-1-5-21-100-200-300-400')

    def test_wrong_descriptor_refused(self):
        self.files['payload/installed-18u-product.json'] = b'{"schema":"installed-18u-product-v1","sourceCommit":"bad","architecture":"native-arm64"}'
        sha = self.write()
        with self.assertRaisesRegex(ValueError, 'identity'):
            make_draft(self.archive, sha, 'S-1-5-21-100-200-300-400')


if __name__ == '__main__':
    unittest.main()
