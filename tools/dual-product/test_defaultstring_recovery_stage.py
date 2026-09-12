import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('recovery_stage', Path(__file__).with_name('stage-defaultstring-recovery.py'))
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class StageTests(unittest.TestCase):
    def test_exact_copy_and_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source'
            source.mkdir()
            (source / 'payload.bin').write_bytes(b'original')
            (source / 'unlisted.txt').write_bytes(b'preserve')
            manifest = root / 'manifest.json'
            raw = json.dumps({'files': [{'path': 'payload.bin', 'bytes': 8, 'sha256': hashlib.sha256(b'original').hexdigest()}]}).encode()
            manifest.write_bytes(raw)
            old = stage.MANIFEST_SHA
            stage.MANIFEST_SHA = hashlib.sha256(raw).hexdigest()
            try:
                output = root / 'staged'
                stage.stage(source, manifest, output)
                self.assertEqual(set(p.name for p in output.iterdir()), {'payload.bin', 'candidate.json'})
                self.assertEqual((source / 'unlisted.txt').read_bytes(), b'preserve')
                with self.assertRaises(ValueError):
                    stage.stage(source, manifest, output)
                (source / 'payload.bin').write_bytes(b'changed!')
                with self.assertRaises(ValueError):
                    stage.stage(source, manifest, root / 'bad')
                self.assertFalse((root / 'bad').exists())
                with self.assertRaises(ValueError):
                    stage.stage(source, manifest, source / 'nested')
            finally:
                stage.MANIFEST_SHA = old


if __name__ == '__main__':
    unittest.main()
