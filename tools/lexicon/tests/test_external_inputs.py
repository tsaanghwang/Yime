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

from yime.lexicon_bundle.external_inputs import (
    ExternalInputError,
    resolve_external_inputs,
)


class ExternalInputTests(unittest.TestCase):
    def test_external_root_resolves_content_locked_input(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            external = root / "external"
            input_path = external / "source" / "sample.txt"
            input_path.parent.mkdir(parents=True)
            input_path.write_text("sample\n", encoding="utf-8")
            lock_path = root / "lock.json"
            lock_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "source/sample.txt",
                                "legacy_path": str(root / "missing.txt"),
                                "size": input_path.stat().st_size,
                                "sha256": hashlib.sha256(
                                    input_path.read_bytes()
                                ).hexdigest(),
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            resolved = resolve_external_inputs(
                lock_path,
                external_root=external,
                allow_legacy_paths=False,
            )
            self.assertEqual(resolved, {"sample": input_path.resolve()})

    def test_changed_external_input_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            input_path = root / "sample.txt"
            input_path.write_text("changed\n", encoding="utf-8")
            lock_path = root / "lock.json"
            lock_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "sample.txt",
                                "legacy_path": str(input_path),
                                "size": input_path.stat().st_size,
                                "sha256": "0" * 64,
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ExternalInputError, "SHA-256"):
                resolve_external_inputs(lock_path)


if __name__ == "__main__":
    unittest.main()
