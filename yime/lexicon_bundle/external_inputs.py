"""Resolve and verify content-locked large lexicon inputs outside Git."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from pathlib import PurePosixPath
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOCK = REPO_ROOT / "tools" / "lexicon" / "data" / "external_inputs.lock.json"
RESTORE_EVIDENCE_SCHEMA = "yime-external-input-restore-evidence-v1"


class ExternalInputError(RuntimeError):
    """Raised when an external input is missing or has changed content."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _lock_records(lock_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    if not isinstance(lock, dict) or lock.get("schema_version") != 1:
        raise ExternalInputError("unsupported external input lock schema")
    if not str(lock.get("lock_id") or ""):
        raise ExternalInputError("external input lock has no lock_id")
    records = lock.get("inputs")
    if not isinstance(records, list) or not records:
        raise ExternalInputError("external input lock is empty")

    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    seen_paths: set[str] = set()
    for raw in records:
        if not isinstance(raw, dict):
            raise ExternalInputError("external input record must be an object")
        input_id = str(raw.get("id") or "")
        if not input_id or input_id in seen:
            raise ExternalInputError(f"invalid or duplicate external input ID: {input_id!r}")
        seen.add(input_id)
        relative_text = str(raw.get("relative_path") or "")
        relative = PurePosixPath(relative_text)
        if (
            not relative_text
            or "\\" in relative_text
            or ":" in relative_text
            or relative.is_absolute()
            or any(part in {"", ".", ".."} for part in relative.parts)
        ):
            raise ExternalInputError(
                f"external input {input_id} has unsafe relative path: {relative_text!r}"
            )
        relative_key = relative.as_posix().casefold()
        if relative_key in seen_paths:
            raise ExternalInputError(
                f"duplicate external input relative path: {relative.as_posix()!r}"
            )
        seen_paths.add(relative_key)
        size = raw.get("size")
        if isinstance(size, bool) or not isinstance(size, int) or size < 0:
            raise ExternalInputError(f"external input {input_id} has invalid size")
        digest = str(raw.get("sha256") or "").lower()
        if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise ExternalInputError(f"external input {input_id} has invalid SHA-256")
        normalized.append(
            {
                **raw,
                "id": input_id,
                "relative_path": relative.as_posix(),
                "size": size,
                "sha256": digest,
            }
        )
    return lock, normalized


def _verify_locked_file(path: Path, raw: dict[str, Any], *, label: str) -> dict[str, Any]:
    input_id = raw["id"]
    if not path.is_file():
        raise ExternalInputError(f"missing {label} {input_id}: {path}")
    size = path.stat().st_size
    if size != raw["size"]:
        raise ExternalInputError(
            f"{label} {input_id} size mismatch: expected {raw['size']}, got {size}"
        )
    digest = _sha256(path)
    if digest != raw["sha256"]:
        raise ExternalInputError(
            f"{label} {input_id} SHA-256 mismatch: expected {raw['sha256']}, got {digest}"
        )
    return {"bytes": size, "sha256": digest, "verified": True}


def _write_json_atomic(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="\n",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as stream:
        temp_path = Path(stream.name)
        json.dump(payload, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    try:
        os.replace(temp_path, path)
    except OSError:
        temp_path.unlink(missing_ok=True)
        raise


def _is_within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_external_inputs(
    lock_path: Path = DEFAULT_LOCK,
    *,
    external_root: Path | None = None,
    allow_legacy_paths: bool = True,
) -> dict[str, Path]:
    """Return verified paths keyed by stable input ID."""
    lock, records = _lock_records(lock_path)
    environment_name = str(lock.get("external_root_environment") or "")
    environment_root = os.environ.get(environment_name, "").strip()
    resolved_root = external_root or (Path(environment_root) if environment_root else None)

    result: dict[str, Path] = {}
    for raw in records:
        input_id = raw["id"]
        candidates: list[Path] = []
        if resolved_root is not None:
            candidates.append(resolved_root / Path(raw["relative_path"]))
        if allow_legacy_paths:
            legacy_path = str(raw.get("legacy_path") or "")
            if legacy_path:
                candidates.append(Path(legacy_path))
        path = next((item for item in candidates if item.is_file()), None)
        if path is None:
            locations = ", ".join(str(item) for item in candidates) or "no configured path"
            raise ExternalInputError(f"missing external input {input_id}: {locations}")
        _verify_locked_file(path, raw, label="external input")
        result[input_id] = path.resolve()
    return result


def run_external_input_restore_drill(
    *,
    archive_root: Path,
    restore_root: Path,
    evidence_path: Path,
    lock_path: Path = DEFAULT_LOCK,
) -> dict[str, Any]:
    """Restore a locked archive into a fresh external directory and record evidence."""
    lock_path = lock_path.resolve()
    archive_root = archive_root.resolve()
    restore_root = restore_root.resolve()
    evidence_path = evidence_path.resolve()
    lock, records = _lock_records(lock_path)
    started_at = _utc_now()
    evidence: dict[str, Any] = {
        "schema_version": RESTORE_EVIDENCE_SCHEMA,
        "decision": "fail",
        "started_at": started_at,
        "completed_at": "",
        "lock": {
            "lock_id": str(lock["lock_id"]),
            "sha256": _sha256(lock_path),
        },
        "archive_root": str(archive_root),
        "restore_root": str(restore_root),
        "input_count": len(records),
        "verified_input_count": 0,
        "total_bytes": sum(raw["size"] for raw in records),
        "inputs": [],
    }
    stage = "preflight"
    current_input = ""
    try:
        if not archive_root.is_dir():
            raise ExternalInputError(f"external archive root is missing: {archive_root}")
        repo_root = REPO_ROOT.resolve()
        if _is_within(archive_root, repo_root):
            raise ExternalInputError(
                f"external archive root must remain outside the Git worktree: {archive_root}"
            )
        if _is_within(restore_root, repo_root):
            raise ExternalInputError(
                f"restore root must remain outside the Git worktree: {restore_root}"
            )
        if _is_within(restore_root, archive_root) or _is_within(
            archive_root, restore_root
        ):
            raise ExternalInputError("archive root and restore root must not overlap")
        if _is_within(evidence_path, archive_root):
            raise ExternalInputError("restore evidence must not modify the external archive")
        if restore_root.exists() and (
            not restore_root.is_dir() or any(restore_root.iterdir())
        ):
            raise ExternalInputError(
                f"restore root must be absent or empty: {restore_root}"
            )

        # Validate every archive member before writing any recovered database.
        for raw in records:
            current_input = raw["id"]
            archive_path = archive_root / Path(raw["relative_path"])
            archive_identity = _verify_locked_file(
                archive_path, raw, label="archived external input"
            )
            evidence["inputs"].append(
                {
                    "id": raw["id"],
                    "relative_path": raw["relative_path"],
                    "expected": {
                        "bytes": raw["size"],
                        "sha256": raw["sha256"],
                    },
                    "archive": archive_identity,
                    "status": "archive_verified",
                }
            )

        stage = "restore"
        restore_root.mkdir(parents=True, exist_ok=True)
        for raw, record in zip(records, evidence["inputs"], strict=True):
            current_input = raw["id"]
            archive_path = archive_root / Path(raw["relative_path"])
            restored_path = restore_root / Path(raw["relative_path"])
            restored_path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                dir=restored_path.parent,
                prefix=f".{restored_path.name}.",
                suffix=".partial",
                delete=False,
            ) as stream:
                partial_path = Path(stream.name)
            try:
                shutil.copyfile(archive_path, partial_path)
                restored_identity = _verify_locked_file(
                    partial_path, raw, label="restored external input"
                )
                os.replace(partial_path, restored_path)
            except Exception:
                partial_path.unlink(missing_ok=True)
                raise
            record["restored"] = restored_identity
            record["status"] = "verified"

        # Re-open the completed tree so the evidence is not based only on temp files.
        stage = "final_verification"
        resolved = resolve_external_inputs(
            lock_path,
            external_root=restore_root,
            allow_legacy_paths=False,
        )
        evidence["verified_input_count"] = len(resolved)
        evidence["decision"] = "pass"
        evidence["completed_at"] = _utc_now()
        _write_json_atomic(evidence_path, evidence)
        return evidence
    except (OSError, ValueError, ExternalInputError) as exc:
        evidence["decision"] = "fail"
        evidence["completed_at"] = _utc_now()
        evidence["verified_input_count"] = sum(
            1 for record in evidence["inputs"] if record.get("status") == "verified"
        )
        evidence["failure"] = {
            "stage": stage,
            "input_id": current_input,
            "message": str(exc),
        }
        _write_json_atomic(evidence_path, evidence)
        if isinstance(exc, ExternalInputError):
            raise
        raise ExternalInputError(str(exc)) from exc


def verify_external_input_restore_evidence(
    evidence_path: Path,
    *,
    lock_path: Path = DEFAULT_LOCK,
) -> dict[str, Any]:
    """Validate restore evidence against the current external-input lock."""
    lock_path = lock_path.resolve()
    evidence_path = evidence_path.resolve()
    lock, records = _lock_records(lock_path)
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    if not isinstance(evidence, dict):
        raise ExternalInputError("external input restore evidence root must be an object")
    if evidence.get("schema_version") != RESTORE_EVIDENCE_SCHEMA:
        raise ExternalInputError("unsupported external input restore evidence schema")
    if evidence.get("decision") != "pass":
        raise ExternalInputError("external input restore evidence decision is not pass")
    if "failure" in evidence:
        raise ExternalInputError("passing external input restore evidence contains failure data")
    for field in ("started_at", "completed_at", "archive_root", "restore_root"):
        if not isinstance(evidence.get(field), str) or not evidence[field].strip():
            raise ExternalInputError(
                f"external input restore evidence has no {field}"
            )
    try:
        started_at = datetime.fromisoformat(
            evidence["started_at"].replace("Z", "+00:00")
        )
        completed_at = datetime.fromisoformat(
            evidence["completed_at"].replace("Z", "+00:00")
        )
    except ValueError as exc:
        raise ExternalInputError(
            "external input restore evidence has an invalid timestamp"
        ) from exc
    if started_at.tzinfo is None or completed_at.tzinfo is None:
        raise ExternalInputError(
            "external input restore evidence timestamps must include a timezone"
        )
    if completed_at < started_at:
        raise ExternalInputError(
            "external input restore evidence completed_at precedes started_at"
        )
    if evidence["archive_root"] == evidence["restore_root"]:
        raise ExternalInputError(
            "external input restore evidence archive and restore roots are identical"
        )
    lock_evidence = evidence.get("lock")
    if not isinstance(lock_evidence, dict):
        raise ExternalInputError("external input restore evidence has no lock identity")
    expected_lock_sha256 = _sha256(lock_path)
    if lock_evidence.get("lock_id") != lock.get("lock_id"):
        raise ExternalInputError("external input restore evidence lock_id mismatch")
    if lock_evidence.get("sha256") != expected_lock_sha256:
        raise ExternalInputError("external input restore evidence lock SHA-256 mismatch")
    if evidence.get("input_count") != len(records):
        raise ExternalInputError("external input restore evidence input_count mismatch")
    if evidence.get("verified_input_count") != len(records):
        raise ExternalInputError(
            "external input restore evidence does not verify every locked input"
        )
    if evidence.get("total_bytes") != sum(raw["size"] for raw in records):
        raise ExternalInputError("external input restore evidence total_bytes mismatch")
    raw_evidence_records = evidence.get("inputs")
    if not isinstance(raw_evidence_records, list):
        raise ExternalInputError("external input restore evidence has no input records")
    evidence_by_id: dict[str, dict[str, Any]] = {}
    for raw in raw_evidence_records:
        if not isinstance(raw, dict):
            raise ExternalInputError("external input restore evidence record is invalid")
        input_id = str(raw.get("id") or "")
        if not input_id or input_id in evidence_by_id:
            raise ExternalInputError(
                f"invalid or duplicate restore evidence input ID: {input_id!r}"
            )
        evidence_by_id[input_id] = raw
    if set(evidence_by_id) != {raw["id"] for raw in records}:
        raise ExternalInputError("external input restore evidence input set mismatch")

    for locked in records:
        restored = evidence_by_id[locked["id"]]
        if restored.get("relative_path") != locked["relative_path"]:
            raise ExternalInputError(
                f"restore evidence {locked['id']} relative path mismatch"
            )
        expected = {"bytes": locked["size"], "sha256": locked["sha256"]}
        if restored.get("expected") != expected:
            raise ExternalInputError(
                f"restore evidence {locked['id']} expected identity mismatch"
            )
        required_identity = {**expected, "verified": True}
        if restored.get("archive") != required_identity:
            raise ExternalInputError(
                f"restore evidence {locked['id']} archive identity mismatch"
            )
        if restored.get("restored") != required_identity:
            raise ExternalInputError(
                f"restore evidence {locked['id']} restored identity mismatch"
            )
        if restored.get("status") != "verified":
            raise ExternalInputError(
                f"restore evidence {locked['id']} status is not verified"
            )
    return {
        "decision": "pass",
        "evidence_path": str(evidence_path),
        "evidence_sha256": _sha256(evidence_path),
        "lock_id": str(lock["lock_id"]),
        "lock_sha256": expected_lock_sha256,
        "input_count": len(records),
        "total_bytes": evidence["total_bytes"],
        "completed_at": evidence.get("completed_at", ""),
    }


def verification_report(paths: dict[str, Path]) -> dict[str, Any]:
    return {
        "decision": "pass",
        "input_count": len(paths),
        "inputs": {key: str(value) for key, value in sorted(paths.items())},
    }
