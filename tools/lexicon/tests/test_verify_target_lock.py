from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_DIR = Path(__file__).resolve().parents[1]
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

from verify_target_lock import VerificationError, verify


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class VerifyTargetLockTests(unittest.TestCase):
    def test_repository_target_lock_passes(self) -> None:
        report = verify()
        self.assertEqual(report["decision"], "pass")
        self.assertEqual(report["target"]["entry_count"], 1167501)
        self.assertEqual(len(report["verified_artifacts"]), 15)

    def test_hash_drift_fails_before_semantic_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = root / "data"
            data.mkdir()
            layout = data / "layout.json"
            layout.write_text(
                json.dumps({"yinyuan_id_to_key": {"M01": "j"}}) + "\n",
                encoding="utf-8",
            )
            source = data / "source.json"
            source.write_text(
                json.dumps(
                    {
                        "entry_count": 1,
                        "distinct_texts": 1,
                        "source_dictionary_sha256": "dict",
                        "source_selection_sha256": "selection",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            runtime = data / "runtime.json"
            runtime.write_text(
                json.dumps(
                    {
                        "entry_count": 1,
                        "source_sha256": "dict",
                        "output_sha256": {},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            profile = data / "profile.json"
            profile.write_text(
                json.dumps({"entry_count_per_mode": 1}) + "\n",
                encoding="utf-8",
            )
            lock = root / "lock.json"
            records = []
            for role, path in (
                ("canonical_layout_projection", layout),
                ("core_source_manifest", source),
                ("three_mode_manifest", runtime),
                ("runtime_profile", profile),
            ):
                records.append(
                    {
                        "role": role,
                        "path": path.relative_to(root).as_posix(),
                        "size": path.stat().st_size,
                        "sha256": _sha256(path),
                    }
                )
            lock.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "lock_id": "fixture",
                        "target": {
                            "entry_count": 1,
                            "distinct_texts": 1,
                            "source_dictionary_sha256": "dict",
                            "source_selection_sha256": "selection",
                            "layout_projection_sha256": hashlib.sha256(
                                b'[["M01","j"]]'
                            ).hexdigest(),
                        },
                        "artifacts": records,
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            source.write_text("{}\n", encoding="utf-8")
            with self.assertRaisesRegex(VerificationError, "size|SHA-256"):
                verify(lock, root)

    def test_candidate_paths_must_be_paired(self) -> None:
        with self.assertRaisesRegex(VerificationError, "provided together"):
            verify(candidate_dictionary=Path("candidate.dict.yaml"))


if __name__ == "__main__":
    unittest.main()
