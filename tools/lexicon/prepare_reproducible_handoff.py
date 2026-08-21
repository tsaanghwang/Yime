#!/usr/bin/env python3
"""Verify two clean rebuilds and prepare evidence for handoff promotion."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


SOURCE_ARTIFACTS = (
    "entries.tsv",
    "reading_conflicts.tsv",
    "rejected_readings.tsv",
    "unencoded_pending_strings.tsv",
    "unresolved_bcc.tsv",
    "character_tiers.tsv",
)
TRIAL_DECISIONS = (
    "candidate_ranking_evidence",
    "long_form_core_migration",
    "dynamic_candidate_coverage",
    "character_coverage",
)


class VerificationError(RuntimeError):
    """Raised when the two rebuilds do not establish one product identity."""


def _read_json(path: Path) -> dict[str, Any]:
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


def _equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise VerificationError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def prepare(
    *,
    source_a: Path,
    trial_a: Path,
    source_b: Path,
    trial_b: Path,
    runtime_database: Path,
    expected_runtime_sha256: str,
    source_date_epoch: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    source_manifests = (
        _read_json(source_a / "manifest.json"),
        _read_json(source_b / "manifest.json"),
    )
    _equal(
        source_manifests[1].get("counts"),
        source_manifests[0].get("counts"),
        "source manifest counts",
    )
    _equal(
        source_manifests[1].get("source_gate_counts"),
        source_manifests[0].get("source_gate_counts"),
        "source manifest source_gate_counts",
    )

    source_artifacts: dict[str, dict[str, object]] = {}
    for name in SOURCE_ARTIFACTS:
        first = source_a / name
        second = source_b / name
        first_hash = _sha256(first)
        second_hash = _sha256(second)
        _equal(second_hash, first_hash, f"source artifact {name} SHA-256")
        _equal(second.stat().st_size, first.stat().st_size, f"source artifact {name} size")
        source_artifacts[name] = {
            "bytes": first.stat().st_size,
            "sha256": first_hash,
        }

    trial_manifests = (
        _read_json(trial_a / "manifest.json"),
        _read_json(trial_b / "manifest.json"),
    )
    for label, manifest in zip(("run_a", "run_b"), trial_manifests):
        for decision_name in TRIAL_DECISIONS:
            decision = manifest.get(decision_name)
            if not isinstance(decision, dict):
                raise VerificationError(
                    f"{label} lacks trial decision {decision_name}"
                )
            _equal(decision.get("decision"), "pass", f"{label} {decision_name}")

    dictionaries = (
        trial_a / "two_level_full.dict.yaml",
        trial_b / "two_level_full.dict.yaml",
    )
    selections = (trial_a / "selection.tsv", trial_b / "selection.tsv")
    dictionary_hash = _sha256(dictionaries[0])
    selection_hash = _sha256(selections[0])
    _equal(_sha256(dictionaries[1]), dictionary_hash, "trial dictionary SHA-256")
    _equal(_sha256(selections[1]), selection_hash, "trial selection SHA-256")

    dictionary_records: list[dict[str, Any]] = []
    for label, manifest in zip(("run_a", "run_b"), trial_manifests):
        record = manifest.get("dictionary")
        if not isinstance(record, dict):
            raise VerificationError(f"{label} lacks dictionary evidence")
        _equal(record.get("output_sha256"), dictionary_hash, f"{label} dictionary manifest")
        _equal(record.get("selection_tsv_sha256"), selection_hash, f"{label} selection manifest")
        dictionary_records.append(record)
    for field in ("total_reading_entries", "total_distinct_texts"):
        _equal(
            dictionary_records[1].get(field),
            dictionary_records[0].get(field),
            f"trial dictionary {field}",
        )

    runtime_hash = _sha256(runtime_database)
    _equal(runtime_hash, expected_runtime_sha256.lower(), "runtime database SHA-256")
    record = dictionary_records[1]
    ranking = record.get("ranking_evidence")
    character_ranking = record.get("single_character_ranking")
    if not isinstance(ranking, dict) or not isinstance(character_ranking, dict):
        raise VerificationError("trial dictionary lacks ranking evidence")

    evidence = {
        "schema_version": "yime-approved-core-evidence-v2",
        "status": "approved_windows_handoff_target",
        "source_dictionary": "yime_core_fixed.dict.yaml",
        "output_sha256": dictionary_hash,
        "selection_tsv_sha256": selection_hash,
        "total_reading_entries": record["total_reading_entries"],
        "total_distinct_texts": record["total_distinct_texts"],
        "distinct_texts_by_length": record["distinct_texts_by_length"],
        "reading_entries_by_length": record["reading_entries_by_length"],
        "single_character_ranking": character_ranking,
        "ranking_evidence": {
            "policy_id": ranking["policy_id"],
            "policy_sha256": ranking["policy_sha256"],
            "distinct_texts_by_source": ranking["distinct_texts_by_source"],
            "missing_selected_source_texts": ranking[
                "missing_selected_source_texts"
            ],
            "raw_bcc_and_lmdg_values_added": ranking[
                "raw_bcc_and_lmdg_values_added"
            ],
        },
        "provenance": {
            "method": "two_identical_clean_rebuilds",
            "source_date_epoch": source_date_epoch,
            "runtime_database": {
                "bytes": runtime_database.stat().st_size,
                "sha256": runtime_hash,
            },
            "source_artifacts": source_artifacts,
            "note": (
                "The current formal process result is the approved Windows "
                "handoff identity; no historical entry-count adjustment was applied."
            ),
        },
    }
    report = {
        "decision": "pass",
        "clean_rebuild_count": 2,
        "source_counts": source_manifests[0].get("counts"),
        "source_gate_counts": source_manifests[0].get("source_gate_counts"),
        "source_artifacts": source_artifacts,
        "runtime_database": evidence["provenance"]["runtime_database"],
        "target": {
            "entry_count": record["total_reading_entries"],
            "distinct_texts": record["total_distinct_texts"],
            "source_dictionary_sha256": dictionary_hash,
            "source_selection_sha256": selection_hash,
        },
        "trial_decisions": {name: "pass" for name in TRIAL_DECISIONS},
    }
    return evidence, report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-a", type=Path, required=True)
    parser.add_argument("--trial-a", type=Path, required=True)
    parser.add_argument("--source-b", type=Path, required=True)
    parser.add_argument("--trial-b", type=Path, required=True)
    parser.add_argument("--runtime-database", type=Path, required=True)
    parser.add_argument("--expected-runtime-sha256", required=True)
    parser.add_argument("--source-date-epoch", type=int, required=True)
    parser.add_argument("--output-evidence", type=Path, required=True)
    parser.add_argument("--output-report", type=Path, required=True)
    args = parser.parse_args()
    try:
        evidence, report = prepare(
            source_a=args.source_a.resolve(),
            trial_a=args.trial_a.resolve(),
            source_b=args.source_b.resolve(),
            trial_b=args.trial_b.resolve(),
            runtime_database=args.runtime_database.resolve(),
            expected_runtime_sha256=args.expected_runtime_sha256,
            source_date_epoch=args.source_date_epoch,
        )
        _write_json(args.output_evidence.resolve(), evidence)
        _write_json(args.output_report.resolve(), report)
    except (KeyError, OSError, VerificationError) as exc:
        print(f"FAIL reproducible handoff preparation: {exc}")
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
