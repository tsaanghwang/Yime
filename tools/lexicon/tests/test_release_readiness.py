from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.lexicon.verify_release_readiness import VerificationError, check_release_readiness
from yime.lexicon_bundle.external_inputs import run_external_input_restore_drill


class ReleaseReadinessTests(unittest.TestCase):
    def test_current_source_reproducibility_is_release_ready(self) -> None:
        report = check_release_readiness()
        self.assertEqual(report["decision"], "pass")
        self.assertTrue(report["release_allowed"])
        self.assertEqual(report["latest_clean_rebuild"]["entry_count"], 1166753)

    def test_tagged_release_gate_accepts_reproduced_source_identity(self) -> None:
        report = check_release_readiness(require_release=True)
        self.assertTrue(report["release_allowed"])

    def test_release_gate_reads_verified_external_restore_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "sample.bin"
            archive.mkdir()
            archived_input.write_bytes(b"locked input")
            lock_path = root / "external.lock.json"
            lock_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "lock_id": "release-gate-restore-test",
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "sample.bin",
                                "size": archived_input.stat().st_size,
                                "sha256": hashlib.sha256(
                                    archived_input.read_bytes()
                                ).hexdigest(),
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            evidence_path = root / "restore-evidence.json"
            run_external_input_restore_drill(
                archive_root=archive,
                restore_root=root / "restore",
                evidence_path=evidence_path,
                lock_path=lock_path,
            )

            report = check_release_readiness(
                require_release=True,
                external_restore_evidence=evidence_path,
                external_input_lock_path=lock_path,
            )

            self.assertTrue(report["release_allowed"])
            self.assertEqual(report["external_input_restore"]["decision"], "pass")
            self.assertEqual(report["external_input_restore"]["input_count"], 1)

    def test_release_gate_rejects_failed_external_restore_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lock_path = root / "external.lock.json"
            lock_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "lock_id": "release-gate-restore-test",
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "sample.bin",
                                "size": 1,
                                "sha256": hashlib.sha256(b"x").hexdigest(),
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            evidence_path = root / "restore-evidence.json"
            evidence_path.write_text(
                json.dumps(
                    {
                        "schema_version": "yime-external-input-restore-evidence-v1",
                        "decision": "fail",
                    }
                ),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(VerificationError, "decision is not pass"):
                check_release_readiness(
                    require_release=True,
                    external_restore_evidence=evidence_path,
                    external_input_lock_path=lock_path,
                )


if __name__ == "__main__":
    unittest.main()
