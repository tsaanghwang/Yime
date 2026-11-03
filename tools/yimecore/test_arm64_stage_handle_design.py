"""Offline file-identity design tests, not Windows handle or ACL acceptance."""

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import tempfile
import unittest


@dataclass(frozen=True)
class FileProof:
    path: str
    device: int
    file_id: int
    size: int
    sha256: str


def proof_from_one_open_file(path: Path) -> FileProof:
    """Model the future same-handle hash and identity check with os.fstat."""
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        digest = hashlib.sha256(stream.read()).hexdigest()
        after = os.fstat(stream.fileno())
    if not before.st_ino or (before.st_dev, before.st_ino, before.st_size,
                              before.st_mtime_ns) != (after.st_dev, after.st_ino,
                                                      after.st_size, after.st_mtime_ns):
        raise ValueError('file identity changed or unavailable during read')
    return FileProof(str(path.absolute()), before.st_dev, before.st_ino,
                     before.st_size, digest)


def require_same_approved_object(expected: FileProof, observed: FileProof) -> None:
    if expected.path != observed.path or (expected.device, expected.file_id) != (
            observed.device, observed.file_id):
        raise ValueError('staged file identity changed')
    if (expected.size, expected.sha256) != (observed.size, observed.sha256):
        raise ValueError('staged file content changed')


class StageHandleDesignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='yime-arm64-file-id-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / 'Setup.ps1'
        self.target.write_bytes(b'approved script')

    def test_unchanged_object_and_bytes_pass(self):
        expected = proof_from_one_open_file(self.target)
        require_same_approved_object(expected, proof_from_one_open_file(self.target))

    def test_same_bytes_replacement_is_not_the_approved_object(self):
        expected = proof_from_one_open_file(self.target)
        replacement = self.root / 'replacement.ps1'
        replacement.write_bytes(b'approved script')
        self.target.rename(self.root / 'original-kept.ps1')
        replacement.rename(self.target)
        observed = proof_from_one_open_file(self.target)
        self.assertEqual(expected.sha256, observed.sha256)
        self.assertNotEqual((expected.device, expected.file_id),
                            (observed.device, observed.file_id))
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            require_same_approved_object(expected, observed)

    def test_different_bytes_replacement_is_rejected(self):
        expected = proof_from_one_open_file(self.target)
        replacement = self.root / 'replacement.ps1'
        replacement.write_bytes(b'different script')
        self.target.rename(self.root / 'original-kept.ps1')
        replacement.rename(self.target)
        with self.assertRaises(ValueError):
            require_same_approved_object(expected, proof_from_one_open_file(self.target))

    def test_in_place_content_change_is_rejected(self):
        expected = proof_from_one_open_file(self.target)
        self.target.write_bytes(b'changed in place')
        observed = proof_from_one_open_file(self.target)
        self.assertEqual((expected.device, expected.file_id),
                         (observed.device, observed.file_id))
        with self.assertRaisesRegex(ValueError, 'content changed'):
            require_same_approved_object(expected, observed)

    def test_other_path_is_not_the_approved_path(self):
        expected = proof_from_one_open_file(self.target)
        other = self.root / 'other.ps1'
        other.write_bytes(b'approved script')
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            require_same_approved_object(expected, proof_from_one_open_file(other))


if __name__ == '__main__':
    unittest.main()
