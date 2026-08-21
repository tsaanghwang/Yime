"""Resolve and verify content-locked large lexicon inputs outside Git."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOCK = REPO_ROOT / "tools" / "lexicon" / "data" / "external_inputs.lock.json"


class ExternalInputError(RuntimeError):
    """Raised when an external input is missing or has changed content."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_external_inputs(
    lock_path: Path = DEFAULT_LOCK,
    *,
    external_root: Path | None = None,
    allow_legacy_paths: bool = True,
) -> dict[str, Path]:
    """Return verified paths keyed by stable input ID."""
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    if lock.get("schema_version") != 1:
        raise ExternalInputError("unsupported external input lock schema")
    environment_name = str(lock.get("external_root_environment") or "")
    environment_root = os.environ.get(environment_name, "").strip()
    resolved_root = external_root or (Path(environment_root) if environment_root else None)
    records = lock.get("inputs")
    if not isinstance(records, list) or not records:
        raise ExternalInputError("external input lock is empty")

    result: dict[str, Path] = {}
    for raw in records:
        if not isinstance(raw, dict):
            raise ExternalInputError("external input record must be an object")
        input_id = str(raw.get("id") or "")
        if not input_id or input_id in result:
            raise ExternalInputError(f"invalid or duplicate external input ID: {input_id!r}")
        candidates: list[Path] = []
        if resolved_root is not None:
            candidates.append(resolved_root / str(raw["relative_path"]))
        if allow_legacy_paths:
            candidates.append(Path(str(raw["legacy_path"])))
        path = next((item for item in candidates if item.is_file()), None)
        if path is None:
            locations = ", ".join(str(item) for item in candidates) or "no configured path"
            raise ExternalInputError(f"missing external input {input_id}: {locations}")
        size = path.stat().st_size
        if size != int(raw["size"]):
            raise ExternalInputError(
                f"external input {input_id} size mismatch: expected {raw['size']}, got {size}"
            )
        digest = _sha256(path)
        if digest != str(raw["sha256"]):
            raise ExternalInputError(
                f"external input {input_id} SHA-256 mismatch: expected {raw['sha256']}, got {digest}"
            )
        result[input_id] = path.resolve()
    return result


def verification_report(paths: dict[str, Path]) -> dict[str, Any]:
    return {
        "decision": "pass",
        "input_count": len(paths),
        "inputs": {key: str(value) for key, value in sorted(paths.items())},
    }
