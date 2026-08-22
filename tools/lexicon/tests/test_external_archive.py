from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.lexicon_bundle.external_archive import (
    create_external_input_bundle,
    materialize_external_archive,
)
from yime.lexicon_bundle.external_inputs import ExternalInputError


class ExternalArchiveTests(unittest.TestCase):
    @staticmethod
    def _write_input_lock(root: Path, content: bytes) -> Path:
        lock_path = root / "external-inputs.lock.json"
        lock_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "lock_id": "external-archive-test-inputs",
                    "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                    "inputs": [
                        {
                            "id": "sample",
                            "relative_path": "source/sample.bin",
                            "size": len(content),
                            "sha256": hashlib.sha256(content).hexdigest(),
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return lock_path

    @staticmethod
    def _write_archive_lock(
        root: Path, input_lock: Path, bundle: dict[str, object]
    ) -> Path:
        archive_lock = root / "external-archive.lock.json"
        archive_lock.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "archive_id": "external-archive-test",
                    "archive_root_environment": "YIME_TEST_ARCHIVE_ROOT",
                    "archive_url_environment": "YIME_TEST_ARCHIVE_URL",
                    "external_inputs": {
                        "lock_id": "external-archive-test-inputs",
                        "sha256": hashlib.sha256(input_lock.read_bytes()).hexdigest(),
                        "input_count": 1,
                        "total_bytes": 6,
                    },
                    "bundle": bundle,
                }
            ),
            encoding="utf-8",
        )
        return archive_lock

    def test_file_url_materializes_a_verified_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source-root"
            sample = source / "source" / "sample.bin"
            sample.parent.mkdir(parents=True)
            sample.write_bytes(b"locked")
            input_lock = self._write_input_lock(root, b"locked")
            bundle_path = root / "external-inputs.zip"
            bundle = create_external_input_bundle(
                source_root=source,
                bundle_path=bundle_path,
                input_lock_path=input_lock,
            )
            archive_lock = self._write_archive_lock(root, input_lock, bundle)
            destination = root / "materialized"

            report = materialize_external_archive(
                archive_root=destination,
                archive_url=bundle_path.as_uri(),
                archive_lock_path=archive_lock,
                input_lock_path=input_lock,
            )

            self.assertEqual(report["decision"], "pass")
            self.assertEqual(report["verified_input_count"], 1)
            self.assertEqual(
                (destination / "source" / "sample.bin").read_bytes(), b"locked"
            )

    def test_materialization_rejects_a_tampered_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source-root"
            sample = source / "source" / "sample.bin"
            sample.parent.mkdir(parents=True)
            sample.write_bytes(b"locked")
            input_lock = self._write_input_lock(root, b"locked")
            bundle_path = root / "external-inputs.zip"
            bundle = create_external_input_bundle(
                source_root=source,
                bundle_path=bundle_path,
                input_lock_path=input_lock,
            )
            archive_lock = self._write_archive_lock(root, input_lock, bundle)
            bundle_path.write_bytes(bundle_path.read_bytes() + b"tampered")

            with self.assertRaisesRegex(ExternalInputError, "size mismatch"):
                materialize_external_archive(
                    archive_root=root / "materialized",
                    archive_url=bundle_path.as_uri(),
                    archive_lock_path=archive_lock,
                    input_lock_path=input_lock,
                )


if __name__ == "__main__":
    unittest.main()
