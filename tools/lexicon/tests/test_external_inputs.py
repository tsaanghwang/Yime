from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.lexicon_bundle.external_inputs import (
    ExternalInputError,
    resolve_external_inputs,
    run_external_input_restore_drill,
    verify_external_input_restore_evidence,
)
from yime import repository_boundary


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
                        "lock_id": "test-external-inputs",
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "source/sample.txt",
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
                        "lock_id": "test-external-inputs",
                        "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                        "inputs": [
                            {
                                "id": "sample",
                                "relative_path": "sample.txt",
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
                resolve_external_inputs(lock_path, external_root=root)

    def test_external_root_is_required_without_repository_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lock_path = self._write_lock(root)
            with self.assertRaisesRegex(ExternalInputError, "external input root is required"):
                resolve_external_inputs(lock_path)

    def test_legacy_path_is_rejected_even_when_external_root_is_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            external = root / "external"
            input_path = external / "source" / "sample.txt"
            input_path.parent.mkdir(parents=True)
            input_path.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            payload = json.loads(lock_path.read_text(encoding="utf-8"))
            payload["inputs"][0]["legacy_path"] = str(input_path)
            lock_path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ExternalInputError, "must not contain legacy_path"):
                resolve_external_inputs(lock_path, external_root=external)

    def test_other_repository_is_blocked_without_approval(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repository = root / "source-repository"
            (repository / ".git").mkdir(parents=True)
            input_path = repository / "source" / "sample.txt"
            input_path.parent.mkdir(parents=True)
            input_path.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            with self.assertRaisesRegex(ExternalInputError, "another repository"):
                resolve_external_inputs(lock_path, external_root=repository)

    def test_reviewed_time_limited_approval_allows_exact_input(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repository = root / "source-repository"
            (repository / ".git").mkdir(parents=True)
            input_path = repository / "source" / "sample.txt"
            input_path.parent.mkdir(parents=True)
            input_path.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            approval_directory = root / "approvals"
            approval_directory.mkdir()
            now = datetime.now(timezone.utc)
            approval_path = approval_directory / "approved.json"
            approval_path.write_text(
                json.dumps(
                    {
                        "schema_version": repository_boundary.APPROVAL_SCHEMA,
                        "decision": "allow",
                        "approval_id": "test-approval",
                        "approved_by": "unit-test",
                        "approved_at": (now - timedelta(minutes=1)).isoformat(),
                        "expires_at": (now + timedelta(days=1)).isoformat(),
                        "authorization_reference": "test-case",
                        "reason": "exercise exact temporary approval",
                        "target_repository": "Yime",
                        "source_repository_root": str(repository.resolve()),
                        "allowed_input_ids": ["sample"],
                    }
                ),
                encoding="utf-8",
            )
            with patch.object(
                repository_boundary,
                "APPROVAL_DIRECTORY",
                approval_directory,
            ):
                resolved = resolve_external_inputs(
                    lock_path,
                    external_root=repository,
                    repository_import_approval=approval_path,
                )
            self.assertEqual(resolved, {"sample": input_path.resolve()})

    @staticmethod
    def _write_lock(root: Path, expected: bytes = b"sample\n") -> Path:
        lock_path = root / "lock.json"
        lock_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "lock_id": "restore-drill-test-lock",
                    "external_root_environment": "YIME_TEST_UNUSED_ROOT",
                    "inputs": [
                        {
                            "id": "sample",
                            "relative_path": "source/sample.txt",
                            "size": len(expected),
                            "sha256": hashlib.sha256(expected).hexdigest(),
                        }
                    ],
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return lock_path

    def test_restore_drill_copies_and_verifies_locked_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            restore = root / "restore"
            evidence_path = root / "evidence.json"

            evidence = run_external_input_restore_drill(
                archive_root=archive,
                restore_root=restore,
                evidence_path=evidence_path,
                lock_path=lock_path,
            )

            self.assertEqual(evidence["decision"], "pass")
            self.assertEqual(evidence["verified_input_count"], 1)
            self.assertEqual((restore / "source" / "sample.txt").read_bytes(), b"sample\n")
            report = verify_external_input_restore_evidence(
                evidence_path, lock_path=lock_path
            )
            self.assertEqual(report["decision"], "pass")
            self.assertEqual(report["input_count"], 1)

    def test_restore_drill_refuses_missing_archive_input_and_replaces_stale_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archive.mkdir()
            lock_path = self._write_lock(root)
            evidence_path = root / "evidence.json"
            evidence_path.write_text('{"decision":"pass"}\n', encoding="utf-8")

            with self.assertRaisesRegex(ExternalInputError, "missing archived"):
                run_external_input_restore_drill(
                    archive_root=archive,
                    restore_root=root / "restore",
                    evidence_path=evidence_path,
                    lock_path=lock_path,
                )

            failure = json.loads(evidence_path.read_text(encoding="utf-8"))
            self.assertEqual(failure["decision"], "fail")
            self.assertEqual(failure["failure"]["stage"], "preflight")
            self.assertFalse((root / "restore").exists())

    def test_restore_drill_refuses_archive_size_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"sample changed\n")
            lock_path = self._write_lock(root)

            with self.assertRaisesRegex(ExternalInputError, "size mismatch"):
                run_external_input_restore_drill(
                    archive_root=archive,
                    restore_root=root / "restore",
                    evidence_path=root / "evidence.json",
                    lock_path=lock_path,
                )

    def test_restore_drill_refuses_archive_hash_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"changed")
            lock_path = self._write_lock(root, expected=b"sample!")

            with self.assertRaisesRegex(ExternalInputError, "SHA-256 mismatch"):
                run_external_input_restore_drill(
                    archive_root=archive,
                    restore_root=root / "restore",
                    evidence_path=root / "evidence.json",
                    lock_path=lock_path,
                )

    def test_restore_drill_refuses_a_destination_inside_the_git_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            repository_destination = REPO_ROOT / ".generated" / "forbidden-restore-test"

            with self.assertRaisesRegex(ExternalInputError, "outside the Git worktree"):
                run_external_input_restore_drill(
                    archive_root=archive,
                    restore_root=repository_destination,
                    evidence_path=root / "evidence.json",
                    lock_path=lock_path,
                )

            self.assertFalse(repository_destination.exists())

    def test_restore_drill_rehashes_the_restored_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)

            def corrupt_copy(_source: Path, destination: Path) -> None:
                Path(destination).write_bytes(b"changed")

            with patch(
                "yime.lexicon_bundle.external_inputs.shutil.copyfile",
                side_effect=corrupt_copy,
            ):
                with self.assertRaisesRegex(ExternalInputError, "restored.*SHA-256"):
                    run_external_input_restore_drill(
                        archive_root=archive,
                        restore_root=root / "restore",
                        evidence_path=root / "evidence.json",
                        lock_path=lock_path,
                    )

            failure = json.loads((root / "evidence.json").read_text(encoding="utf-8"))
            self.assertEqual(failure["decision"], "fail")
            self.assertEqual(failure["failure"]["stage"], "restore")

    def test_release_evidence_rejects_tampered_restored_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "archive"
            archived_input = archive / "source" / "sample.txt"
            archived_input.parent.mkdir(parents=True)
            archived_input.write_bytes(b"sample\n")
            lock_path = self._write_lock(root)
            evidence_path = root / "evidence.json"
            run_external_input_restore_drill(
                archive_root=archive,
                restore_root=root / "restore",
                evidence_path=evidence_path,
                lock_path=lock_path,
            )
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            evidence["inputs"][0]["restored"]["sha256"] = "0" * 64
            evidence_path.write_text(json.dumps(evidence), encoding="utf-8")

            with self.assertRaisesRegex(ExternalInputError, "restored identity mismatch"):
                verify_external_input_restore_evidence(
                    evidence_path, lock_path=lock_path
                )


if __name__ == "__main__":
    unittest.main()
