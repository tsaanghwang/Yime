"""Create and materialize the content-locked external lexicon archive."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from yime.lexicon_bundle.external_inputs import (
    DEFAULT_LOCK,
    REPO_ROOT,
    ExternalInputError,
    _lock_records,
    resolve_external_inputs,
)


DEFAULT_ARCHIVE_LOCK = (
    REPO_ROOT / "tools" / "lexicon" / "data" / "external_archive.lock.json"
)
ZIP_TIMESTAMP = (2026, 8, 21, 0, 0, 0)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _is_within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def verify_external_archive_lock(
    archive_lock_path: Path, input_lock_path: Path
) -> dict[str, Any]:
    archive_lock = json.loads(archive_lock_path.read_text(encoding="utf-8"))
    if not isinstance(archive_lock, dict) or archive_lock.get("schema_version") != 1:
        raise ExternalInputError("unsupported external archive lock schema")
    input_lock, records = _lock_records(input_lock_path)
    locked_inputs = archive_lock.get("external_inputs")
    if not isinstance(locked_inputs, dict):
        raise ExternalInputError("external archive lock has no input-lock identity")
    expected = {
        "lock_id": input_lock["lock_id"],
        "sha256": _sha256(input_lock_path),
        "input_count": len(records),
        "total_bytes": sum(record["size"] for record in records),
    }
    for field, value in expected.items():
        if locked_inputs.get(field) != value:
            raise ExternalInputError(
                f"external archive lock input {field} mismatch: "
                f"expected {value!r}, got {locked_inputs.get(field)!r}"
            )
    bundle = archive_lock.get("bundle")
    if not isinstance(bundle, dict) or bundle.get("format") != "zip":
        raise ExternalInputError("external archive lock has no ZIP bundle identity")
    size = bundle.get("size")
    digest = str(bundle.get("sha256") or "").lower()
    if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
        raise ExternalInputError("external archive bundle has invalid size")
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ExternalInputError("external archive bundle has invalid SHA-256")
    return archive_lock


def create_external_input_bundle(
    *,
    source_root: Path,
    bundle_path: Path,
    input_lock_path: Path = DEFAULT_LOCK,
) -> dict[str, Any]:
    """Write a deterministic ZIP containing exactly the locked input files."""
    source_root = source_root.resolve()
    bundle_path = bundle_path.resolve()
    repo_root = REPO_ROOT.resolve()
    if _is_within(bundle_path, repo_root):
        raise ExternalInputError(
            f"external input bundle must remain outside the Git worktree: {bundle_path}"
        )
    _, records = _lock_records(input_lock_path.resolve())
    resolve_external_inputs(input_lock_path, external_root=source_root)
    bundle_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=bundle_path.parent,
        prefix=f".{bundle_path.name}.",
        suffix=".partial",
        delete=False,
    ) as stream:
        partial_path = Path(stream.name)
    try:
        with zipfile.ZipFile(
            partial_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            for record in sorted(records, key=lambda item: item["relative_path"]):
                info = zipfile.ZipInfo(record["relative_path"], ZIP_TIMESTAMP)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                with (source_root / record["relative_path"]).open("rb") as source:
                    archive.writestr(info, source.read(), compresslevel=9)
        os.replace(partial_path, bundle_path)
    except Exception:
        partial_path.unlink(missing_ok=True)
        raise
    return {
        "filename": bundle_path.name,
        "format": "zip",
        "size": bundle_path.stat().st_size,
        "sha256": _sha256(bundle_path),
    }


def materialize_external_archive(
    *,
    archive_root: Path | None = None,
    archive_url: str | None = None,
    archive_lock_path: Path = DEFAULT_ARCHIVE_LOCK,
    input_lock_path: Path = DEFAULT_LOCK,
) -> dict[str, Any]:
    """Verify an existing archive root or download and safely materialize it."""
    archive_lock_path = archive_lock_path.resolve()
    input_lock_path = input_lock_path.resolve()
    archive_lock = verify_external_archive_lock(archive_lock_path, input_lock_path)
    root_environment = str(archive_lock.get("archive_root_environment") or "")
    url_environment = str(archive_lock.get("archive_url_environment") or "")
    root_text = os.environ.get(root_environment, "").strip()
    resolved_root = (archive_root or (Path(root_text) if root_text else None))
    if resolved_root is None:
        raise ExternalInputError(
            f"external archive root is required; pass --archive-root or set {root_environment}"
        )
    resolved_root = resolved_root.resolve()
    if _is_within(resolved_root, REPO_ROOT.resolve()):
        raise ExternalInputError(
            f"external archive root must remain outside the Git worktree: {resolved_root}"
        )
    if resolved_root.is_dir() and any(resolved_root.iterdir()):
        paths = resolve_external_inputs(input_lock_path, external_root=resolved_root)
        return {
            "decision": "pass",
            "source": "existing_root",
            "archive_root": str(resolved_root),
            "verified_input_count": len(paths),
        }
    if resolved_root.exists() and not resolved_root.is_dir():
        raise ExternalInputError(f"external archive root is not a directory: {resolved_root}")

    configured_url = (archive_url or os.environ.get(url_environment, "")).strip()
    if not configured_url:
        raise ExternalInputError(
            f"external archive URL is required; pass --archive-url or set {url_environment}"
        )
    parsed = urlparse(configured_url)
    if parsed.scheme not in {"https", "file"}:
        raise ExternalInputError("external archive URL must use https:// or file://")

    bundle = archive_lock["bundle"]
    resolved_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=resolved_root.parent, prefix=f".{resolved_root.name}."
    ) as temporary:
        stage_root = Path(temporary) / "archive"
        bundle_path = Path(temporary) / str(bundle["filename"])
        with urllib.request.urlopen(configured_url, timeout=120) as response:
            with bundle_path.open("wb") as destination:
                shutil.copyfileobj(response, destination, length=1024 * 1024)
        if bundle_path.stat().st_size != bundle["size"]:
            raise ExternalInputError("external archive bundle size mismatch")
        if _sha256(bundle_path) != bundle["sha256"]:
            raise ExternalInputError("external archive bundle SHA-256 mismatch")

        _, records = _lock_records(input_lock_path)
        expected_members = {record["relative_path"] for record in records}
        stage_root.mkdir()
        with zipfile.ZipFile(bundle_path) as archive:
            actual_members = {info.filename for info in archive.infolist() if not info.is_dir()}
            if actual_members != expected_members:
                raise ExternalInputError("external archive bundle member set mismatch")
            for record in records:
                destination = stage_root / record["relative_path"]
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(record["relative_path"]) as source:
                    with destination.open("wb") as output:
                        shutil.copyfileobj(source, output, length=1024 * 1024)
        paths = resolve_external_inputs(input_lock_path, external_root=stage_root)
        if resolved_root.exists():
            resolved_root.rmdir()
        os.replace(stage_root, resolved_root)
    return {
        "decision": "pass",
        "source": configured_url,
        "archive_root": str(resolved_root),
        "bundle_sha256": bundle["sha256"],
        "verified_input_count": len(paths),
    }
