#!/usr/bin/env python3
"""Verify the immutable Phase 0 Windows lexicon handoff target."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOCK = Path(__file__).resolve().parent / "data" / "yime_core_target.lock.json"


class VerificationError(RuntimeError):
    """Raised when a locked artifact or semantic identity drifts."""


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VerificationError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VerificationError(f"JSON root must be an object: {path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise VerificationError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _expect(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise VerificationError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def _layout_projection_digest(layout_path: Path) -> str:
    payload = _load_json(layout_path)
    mapping = payload.get("yinyuan_id_to_key")
    if not isinstance(mapping, dict) or not mapping:
        raise VerificationError(
            f"layout has no yinyuan_id_to_key mapping: {layout_path}"
        )
    normalized = json.dumps(
        sorted((str(key), str(value)) for key, value in mapping.items()),
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(normalized).hexdigest()


def verify(
    lock_path: Path = DEFAULT_LOCK,
    repo_root: Path = REPO_ROOT,
    *,
    candidate_dictionary: Path | None = None,
    candidate_selection: Path | None = None,
) -> dict[str, Any]:
    """Verify locked files and optionally require an exact candidate match."""
    if (candidate_dictionary is None) != (candidate_selection is None):
        raise VerificationError(
            "candidate dictionary and selection must be provided together"
        )

    lock = _load_json(lock_path)
    _expect(lock.get("schema_version"), 1, "lock schema_version")
    target = lock.get("target")
    artifacts = lock.get("artifacts")
    if not isinstance(target, dict) or not isinstance(artifacts, list):
        raise VerificationError("lock must contain target and artifacts")

    verified: list[dict[str, object]] = []
    role_paths: dict[str, Path] = {}
    for index, record in enumerate(artifacts):
        if not isinstance(record, dict):
            raise VerificationError(f"artifact {index} must be an object")
        role = str(record.get("role", ""))
        relative = str(record.get("path", ""))
        if not role or not relative:
            raise VerificationError(f"artifact {index} lacks role or path")
        if role in role_paths:
            raise VerificationError(f"duplicate artifact role: {role}")
        path = (repo_root / relative).resolve()
        try:
            path.relative_to(repo_root.resolve())
        except ValueError as exc:
            raise VerificationError(
                f"artifact escapes repository root: {relative}"
            ) from exc
        if not path.is_file():
            raise VerificationError(f"locked artifact is missing: {relative}")
        size = path.stat().st_size
        digest = _sha256(path)
        _expect(size, record.get("size"), f"{role} size")
        _expect(digest, record.get("sha256"), f"{role} SHA-256")
        role_paths[role] = path
        verified.append(
            {"role": role, "path": relative, "size": size, "sha256": digest}
        )

    source = _load_json(role_paths["core_source_manifest"])
    runtime = _load_json(role_paths["three_mode_manifest"])
    profile = _load_json(role_paths["runtime_profile"])
    _expect(source.get("entry_count"), target.get("entry_count"), "source entry_count")
    _expect(
        source.get("distinct_texts"),
        target.get("distinct_texts"),
        "source distinct_texts",
    )
    _expect(
        source.get("source_dictionary_sha256"),
        target.get("source_dictionary_sha256"),
        "source dictionary SHA-256",
    )
    _expect(
        source.get("source_selection_sha256"),
        target.get("source_selection_sha256"),
        "source selection SHA-256",
    )
    _expect(runtime.get("entry_count"), target.get("entry_count"), "runtime entry_count")
    _expect(
        runtime.get("source_sha256"),
        target.get("source_dictionary_sha256"),
        "runtime source SHA-256",
    )
    _expect(
        profile.get("entry_count_per_mode"),
        target.get("entry_count"),
        "runtime profile entry_count_per_mode",
    )
    output_hashes = runtime.get("output_sha256")
    if not isinstance(output_hashes, dict):
        raise VerificationError("runtime manifest lacks output_sha256")
    for role, filename in (
        ("full_mode_dictionary", "yime_full.dict.yaml"),
        ("variable_mode_dictionary", "yime_variable.dict.yaml"),
        ("shorthand_mode_dictionary", "yime_shorthand.dict.yaml"),
    ):
        _expect(
            output_hashes.get(filename),
            _sha256(role_paths[role]),
            f"runtime manifest {filename} SHA-256",
        )
    layout_digest = _layout_projection_digest(
        role_paths["canonical_layout_projection"]
    )
    _expect(
        layout_digest,
        target.get("layout_projection_sha256"),
        "layout projection SHA-256",
    )

    candidate_report: dict[str, object] | None = None
    if candidate_dictionary is not None and candidate_selection is not None:
        dictionary_hash = _sha256(candidate_dictionary.resolve())
        selection_hash = _sha256(candidate_selection.resolve())
        _expect(
            dictionary_hash,
            target.get("source_dictionary_sha256"),
            "candidate dictionary SHA-256",
        )
        _expect(
            selection_hash,
            target.get("source_selection_sha256"),
            "candidate selection SHA-256",
        )
        candidate_report = {
            "dictionary": str(candidate_dictionary.resolve()),
            "dictionary_sha256": dictionary_hash,
            "selection": str(candidate_selection.resolve()),
            "selection_sha256": selection_hash,
            "candidate_exact_match": True,
        }

    return {
        "decision": "pass",
        "lock_id": lock.get("lock_id"),
        "target": target,
        "verified_artifacts": verified,
        "layout_projection_sha256": layout_digest,
        "candidate": candidate_report,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--candidate-dictionary", type=Path)
    parser.add_argument("--candidate-selection", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = verify(
            args.lock.resolve(),
            args.repo_root.resolve(),
            candidate_dictionary=args.candidate_dictionary,
            candidate_selection=args.candidate_selection,
        )
    except VerificationError as exc:
        print(f"FAIL target lexicon lock: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
