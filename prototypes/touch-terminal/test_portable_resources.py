"""Archive boundary checks with tiny synthetic bytes, never acceptance corpus."""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import touch_keyboard_resources as resources


class ResourceArchiveBoundary(unittest.TestCase):
    def archive(self, root, extra=None):
        archive=root/'fixture.zip'
        files={name: ('synthetic '+name).encode() for name in resources.NAMES}
        with zipfile.ZipFile(archive,'w') as z:
            for name,body in files.items(): z.writestr(name,body)
            if extra: z.writestr(extra,b'escape')
        lock={'schemaVersion':1,'archiveBytes':archive.stat().st_size,'archiveSHA256':resources.digest(archive),
              'files':{name:{'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()} for name,body in files.items()}}
        return archive,lock

    def test_exact_inventory_extracts_and_detects_existing_corruption(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); archive,lock=self.archive(root); output=root/'restored'
            with patch.object(resources,'generated',side_effect=lambda p:Path(p)), patch.object(resources,'validate_manifest',return_value={}):
                resources.extract(archive,output,lock)
                resources.extract(archive,output,lock)
                (output/resources.NAMES[1]).write_bytes(b'changed')
                with self.assertRaises(ValueError): resources.extract(archive,output,lock)

    def test_digest_and_traversal_archives_fail_closed(self):
        for extra in (None,'../escape','unlisted.txt'):
            with self.subTest(extra=extra),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); archive,lock=self.archive(root,extra)
                if extra is None: lock['archiveSHA256']='0'*64
                with patch.object(resources,'generated',side_effect=lambda p:Path(p)):
                    with self.assertRaises(ValueError): resources.extract(archive,root/'output',lock)
                self.assertFalse((root/'escape').exists())

    def test_checked_in_lock_matches_current_physical_projection(self):
        lock=json.loads(resources.LOCK.read_text(encoding='utf-8'))
        layout=json.loads((ROOT/'prototypes/touch-terminal/data/physical-layout.json').read_text(encoding='utf-8'))
        self.assertEqual(lock['layoutProjectionSHA256'],layout['layoutId'])
        self.assertEqual(set(lock['files']),set(resources.NAMES))


if __name__=='__main__': unittest.main()
