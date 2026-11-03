"""Offline regression coverage for pinned downloads and source archive boundaries."""
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from prepare_dependencies import download, unpack


class BuildInputTests(unittest.TestCase):
    def test_cached_download_rejects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory)/'source.tar.gz'
            archive.write_bytes(b'changed archive')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                download('https://unused.invalid/source', archive, hashlib.sha256(b'expected archive').hexdigest())

    def test_archive_rejects_traversal_and_links(self):
        for name, kind in [('root/../../escape', tarfile.REGTYPE),
                           ('root/link', tarfile.SYMTYPE), ('root/hardlink', tarfile.LNKTYPE)]:
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory)/'source.tar.gz'
                with tarfile.open(archive, 'w:gz') as output:
                    item = tarfile.TarInfo(name)
                    item.type = kind
                    item.linkname = '../../escape'
                    if kind == tarfile.REGTYPE:
                        item.size = 1
                        output.addfile(item, io.BytesIO(b'x'))
                    else:
                        output.addfile(item)
                with self.assertRaisesRegex(ValueError, 'unsafe source archive member'):
                    unpack(archive, Path(directory)/'unpacked')
                self.assertFalse((Path(directory)/'escape').exists())

    def test_archive_does_not_overwrite_an_existing_unmarked_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory)/'source.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                item = tarfile.TarInfo('root/file')
                item.size = 3
                output.addfile(item, io.BytesIO(b'new'))
            tree = Path(directory)/'unpacked'
            tree.mkdir()
            (tree/'file').write_bytes(b'preserve')
            with self.assertRaisesRegex(ValueError, 'refuse existing source directory'):
                unpack(archive, tree)
            self.assertEqual((tree/'file').read_bytes(), b'preserve')


if __name__ == '__main__':
    unittest.main()
