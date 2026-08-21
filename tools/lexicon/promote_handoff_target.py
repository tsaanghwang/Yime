#!/usr/bin/env python3
"""Promote a verified clean rebuild into the canonical Windows handoff."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class PromotionError(RuntimeError):
    """Raised before promotion if evidence or staging is incomplete."""


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PromotionError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PromotionError(f"JSON root must be an object: {path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise PromotionError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _expect(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise PromotionError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def _layout_digest(path: Path) -> str:
    mapping = _read_json(path).get("yinyuan_id_to_key")
    if not isinstance(mapping, dict) or not mapping:
        raise PromotionError(f"layout has no yinyuan_id_to_key mapping: {path}")
    normalized = json.dumps(
        sorted((str(key), str(value)) for key, value in mapping.items()),
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(normalized).hexdigest()


def _atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix=destination.name + ".",
        suffix=".tmp",
        dir=destination.parent,
        delete=False,
    ) as stream:
        temporary = Path(stream.name)
    try:
        shutil.copyfile(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def _atomic_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode(
        "utf-8"
    )
    with tempfile.NamedTemporaryFile(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
        delete=False,
    ) as stream:
        temporary = Path(stream.name)
        stream.write(encoded)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def promote(
    *,
    repo_root: Path,
    candidate_dictionary: Path,
    candidate_evidence: Path,
    reproducibility_report: Path,
    stage_data_dir: Path,
    source_revision: str,
    apply: bool,
) -> dict[str, Any]:
    data_dir = repo_root / "go-backend" / "input_methods" / "yime" / "data"
    handoff_dir = repo_root / "tools" / "lexicon" / "handoff"
    lock_path = repo_root / "tools" / "lexicon" / "data" / "yime_core_target.lock.json"
    status_path = (
        repo_root
        / "tools"
        / "lexicon"
        / "data"
        / "source_reproducibility.status.json"
    )
    previous_lock = _read_json(lock_path)
    evidence = _read_json(candidate_evidence)
    report = _read_json(reproducibility_report)
    runtime_manifest = _read_json(stage_data_dir / "yime_lexicon_manifest.json")
    source_manifest = _read_json(stage_data_dir / "yime_core_source_manifest.json")

    _expect(report.get("decision"), "pass", "reproducibility decision")
    _expect(report.get("clean_rebuild_count"), 2, "clean rebuild count")
    dictionary_hash = _sha256(candidate_dictionary)
    _expect(evidence.get("output_sha256"), dictionary_hash, "evidence dictionary SHA-256")
    target = report.get("target")
    if not isinstance(target, dict):
        raise PromotionError("reproducibility report has no target")
    _expect(target.get("source_dictionary_sha256"), dictionary_hash, "report dictionary SHA-256")
    for field in ("entry_count", "distinct_texts"):
        evidence_field = (
            "total_reading_entries" if field == "entry_count" else "total_distinct_texts"
        )
        _expect(evidence.get(evidence_field), target.get(field), f"evidence {field}")
        _expect(source_manifest.get(field), target.get(field), f"staged source {field}")
    _expect(runtime_manifest.get("entry_count"), target.get("entry_count"), "staged runtime entry_count")
    _expect(runtime_manifest.get("source_sha256"), dictionary_hash, "staged runtime source SHA-256")
    _expect(source_manifest.get("source_dictionary_sha256"), dictionary_hash, "staged source dictionary SHA-256")
    _expect(
        source_manifest.get("source_selection_sha256"),
        target.get("source_selection_sha256"),
        "staged source selection SHA-256",
    )
    _expect(source_manifest.get("source_revision"), source_revision, "staged source revision")

    stage_files = sorted(path for path in stage_data_dir.rglob("*") if path.is_file())
    if not stage_files:
        raise PromotionError(f"staging data directory is empty: {stage_data_dir}")
    layout_digest = _layout_digest(stage_data_dir / "yime_yinyuan_layout.json")
    planned = {
        "decision": "pass",
        "apply_requested": apply,
        "stage_file_count": len(stage_files),
        "source_revision": source_revision,
        "target": {**target, "layout_projection_sha256": layout_digest},
        "supersedes": {
            "lock_id": previous_lock.get("lock_id"),
            "target": previous_lock.get("target"),
        },
    }
    if not apply:
        return planned

    for source in stage_files:
        relative = source.relative_to(stage_data_dir)
        _atomic_copy(source, data_dir / relative)
    canonical_dictionary = handoff_dir / "yime_core_fixed.dict.yaml"
    canonical_evidence = handoff_dir / "yime_core_fixed.evidence.json"
    _atomic_copy(candidate_dictionary, canonical_dictionary)
    _atomic_copy(candidate_evidence, canonical_evidence)

    artifact_records: list[dict[str, object]] = []
    for old_record in previous_lock.get("artifacts", []):
        if not isinstance(old_record, dict):
            raise PromotionError("previous target lock has an invalid artifact record")
        relative = str(old_record.get("path", ""))
        role = str(old_record.get("role", ""))
        path = repo_root / relative
        if not role or not relative or not path.is_file():
            raise PromotionError(f"promoted artifact is missing: {role} {relative}")
        artifact_records.append(
            {
                "role": role,
                "path": relative,
                "size": path.stat().st_size,
                "sha256": _sha256(path),
            }
        )

    build_epoch = int(evidence["provenance"]["source_date_epoch"])
    recorded_at = datetime.fromtimestamp(build_epoch, tz=UTC).isoformat().replace(
        "+00:00", "Z"
    )
    new_target = {
        "entry_count": target["entry_count"],
        "distinct_texts": target["distinct_texts"],
        "source_dictionary_sha256": target["source_dictionary_sha256"],
        "source_selection_sha256": target["source_selection_sha256"],
        "layout_projection_sha256": layout_digest,
    }
    new_lock = {
        "schema_version": 1,
        "lock_id": (
            f"yime-core-{target['entry_count']}-layout-{layout_digest[:12]}"
        ),
        "status": "approved_windows_handoff_target",
        "source": {
            "project": "Yime",
            "recorded_revision": source_revision,
            "note": (
                "Approved from two identical clean rebuilds using the formal "
                "in-repository source and encoding chain."
            ),
        },
        "supersedes": planned["supersedes"],
        "target": new_target,
        "artifacts": artifact_records,
    }
    rebuild = {
        "recorded_at": recorded_at,
        **{key: new_target[key] for key in (
            "entry_count",
            "distinct_texts",
            "source_dictionary_sha256",
            "source_selection_sha256",
        )},
    }
    previous_target = previous_lock.get("target", {})
    status = {
        "schema_version": 1,
        "decision": "pass",
        "target_lock": lock_path.name,
        "target": {key: new_target[key] for key in (
            "entry_count",
            "distinct_texts",
            "source_dictionary_sha256",
            "source_selection_sha256",
        )},
        "latest_clean_rebuild": {"run": "clean-rebuild-b", **rebuild},
        "clean_rebuilds": [
            {"run": "clean-rebuild-a", **rebuild},
            {"run": "clean-rebuild-b", **rebuild},
        ],
        "promotion": {
            "source_revision": source_revision,
            "source_date_epoch": build_epoch,
            "reproducibility_report_sha256": _sha256(reproducibility_report),
            "runtime_database": evidence["provenance"]["runtime_database"],
            "previous_target": previous_target,
            "entry_delta_from_previous_target": (
                int(new_target["entry_count"])
                - int(previous_target.get("entry_count", 0))
            ),
            "distinct_text_delta_from_previous_target": (
                int(new_target["distinct_texts"])
                - int(previous_target.get("distinct_texts", 0))
            ),
        },
        "blocking_reason": "",
        "required_resolution": "",
        "safeguards": {
            "baseline_update_allowed": True,
            "derived_dictionary_overwrite_allowed": True,
            "pinyin_code_edit_allowed": False,
            "tagged_release_allowed": True,
        },
    }
    _atomic_json(lock_path, new_lock)
    _atomic_json(status_path, status)
    planned["lock_id"] = new_lock["lock_id"]
    planned["artifact_count"] = len(artifact_records)
    return planned


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--candidate-dictionary", type=Path, required=True)
    parser.add_argument("--candidate-evidence", type=Path, required=True)
    parser.add_argument("--reproducibility-report", type=Path, required=True)
    parser.add_argument("--stage-data-dir", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        report = promote(
            repo_root=args.repo_root.resolve(),
            candidate_dictionary=args.candidate_dictionary.resolve(),
            candidate_evidence=args.candidate_evidence.resolve(),
            reproducibility_report=args.reproducibility_report.resolve(),
            stage_data_dir=args.stage_data_dir.resolve(),
            source_revision=args.source_revision,
            apply=args.apply,
        )
    except (KeyError, OSError, PromotionError) as exc:
        print(f"FAIL handoff promotion: {exc}")
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
