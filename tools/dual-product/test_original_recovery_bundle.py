"""Authentication and no-partial-output checks for the recovery data extractor."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

spec = importlib.util.spec_from_file_location('extractor', Path(__file__).with_name('extract-original-recovery-bundle.py'))
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


class ExtractionTests(unittest.TestCase):
    def exercise(self, case):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = '../outside' if case == 'traversal' else 'payload/a.bin'
            data = b'original'
            manifest = json.dumps({'files': [{'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}]}).encode()
            archive = root / 'bundle.zip'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(archive, 'w') as z:
                    z.writestr('candidate.json', manifest)
                    z.writestr(name, b'corrupt!' if case == 'tampered' else data)
                    if case == 'duplicate':
                        z.writestr(name, data)
                    if case == 'extra':
                        z.writestr('extra', data)
            output = root / 'output'
            if case == 'existing':
                output.mkdir()
                (output / 'keep').write_bytes(b'keep')
            sha = '0' * 64 if case == 'wrong_manifest' else hashlib.sha256(manifest).hexdigest()
            with patch.object(extractor, 'MANIFEST_SHA', sha):
                if case == 'valid':
                    result = extractor.extract(archive, output)
                    self.assertFalse(result['executed'])
                    self.assertEqual((output / name).read_bytes(), data)
                else:
                    with self.assertRaises(ValueError):
                        extractor.extract(archive, output)
                    if case == 'existing':
                        self.assertEqual(list(output.iterdir()), [output / 'keep'])
                    else:
                        self.assertFalse(output.exists())

    def test_authenticated_fresh_tree(self):
        self.exercise('valid')

    def test_rejections_create_no_payload(self):
        for case in ('traversal', 'tampered', 'duplicate', 'extra', 'existing', 'wrong_manifest'):
            with self.subTest(case=case):
                self.exercise(case)


if __name__ == '__main__':
    unittest.main()
