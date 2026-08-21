"""Build and materialize the replay-validated two-level runtime lexicon.

This is the single experimental entry point for:

1. rebuilding the B-lite source-backed selection;
2. retaining every tier-1..8 formally encoded single character and the
   source-backed 1-4 character components built from them;
3. retaining selected long bridges plus a bounded high-weight long cache;
4. cloning the complete prototype database; and
5. activating the selection only on its materialized runtime candidates.

The source bundle and full inventory tables are never reduced.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Mapping

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.build_two_level_precomposition_lexicon import (
    build as build_two_level_dictionary,
)
from tools.prepare_component_learning_trial import build_dictionary
from yime.input_model.core_trial_export import export_core_trial_lexicons
from yime.input_model.dynamic_coverage import (
    evaluate_dynamic_candidate_coverage,
)
from yime.input_model.long_form_migration import (
    audit_long_form_core_migration,
)
from yime.input_model.ranking_evidence import (
    audit_runtime_ranking_evidence,
)
from yime.utils.rime_export import export_rime_files
from yime.utils.runtime_lexicon_selection import (
    apply_runtime_selection,
    clone_database,
)


DEFAULT_POLICY = (
    ROOT / "internal_data" / "runtime_lexicon_filter_policy.json"
)
DEFAULT_SOURCE = (
    ROOT
    / ".generated"
    / "lexicon_source_bundle"
    / "source_lexicon.sqlite3"
)
DEFAULT_CAPACITY = (
    ROOT
    / ".generated"
    / "static_lexicon_capacity"
    / "static_capacity.sqlite3"
)
DEFAULT_RUNTIME = ROOT / "yime" / "pinyin_hanzi.db"
DEFAULT_INPUT_MODEL = (
    ROOT / ".generated" / "input_candidate_model" / "input_model.sqlite3"
)
DEFAULT_OUTPUT = ROOT / ".generated" / "two_level_runtime_trial"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _assert_character_boundary(
    manifest: Mapping[str, object],
    character_policy: Mapping[str, object],
    *,
    label: str,
    expected_readings_field: str,
) -> dict[str, int]:
    expected_characters = int(
        character_policy["expected_distinct_characters"]
    )
    expected_readings = int(
        character_policy[expected_readings_field]
    )
    distinct_by_length = manifest.get("distinct_texts_by_length")
    readings_by_length = manifest.get("reading_entries_by_length")
    if not isinstance(distinct_by_length, Mapping) or not isinstance(
        readings_by_length, Mapping
    ):
        raise ValueError(
            f"{label} manifest has no per-length completeness counts"
        )
    actual_characters = int(distinct_by_length.get("1", 0))
    actual_readings = int(readings_by_length.get("1", 0))
    if actual_characters != expected_characters:
        raise ValueError(
            f"{label} single-character coverage mismatch: expected "
            f"{expected_characters}, got {actual_characters}"
        )
    if actual_readings != expected_readings:
        raise ValueError(
            f"{label} single-character reading coverage mismatch: expected "
            f"{expected_readings}, got {actual_readings}"
        )
    allowed_characters = manifest.get("allowed_encoded_hanzi")
    if allowed_characters is not None and (
        int(allowed_characters) != expected_characters
    ):
        raise ValueError(
            f"{label} allowed-character inventory mismatch: expected "
            f"{expected_characters}, got {allowed_characters}"
        )
    return {
        "distinct_characters": actual_characters,
        "reading_entries": actual_readings,
    }


def build_trial(
    *,
    policy_path: Path,
    source_database: Path,
    capacity_database: Path,
    input_model_database: Path,
    source_runtime_database: Path,
    output_dir: Path,
    reuse_runtime_database: bool = False,
    materialize_runtime_database: bool = True,
) -> dict[str, object]:
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    character_policy = policy["character_boundary"]
    first_level_policy = policy["first_level"]
    second_level_policy = policy["second_level"]
    character_ranking_policy = policy["single_character_ranking"]
    ranking_gate = policy["candidate_ranking_evidence_gate"]
    ranking_policy_path = ROOT / str(ranking_gate["policy"])
    maximum_tier = int(character_policy["maximum_tier"])

    core_output = output_dir / "core_selection"
    core_result = export_core_trial_lexicons(
        source_database=source_database,
        capacity_database=capacity_database,
        output_dir=core_output,
        capacities=(int(first_level_policy["capacity_base"]),),
        include_source_lengths={
            str(source): tuple(int(item) for item in lengths)
            for source, lengths in first_level_policy[
                "included_source_lengths"
            ].items()
        },
        include_wanxiang_category_lengths={
            str(category): tuple(int(item) for item in lengths)
            for category, lengths in first_level_policy[
                "included_wanxiang_category_lengths"
            ].items()
        },
        trial_label="all-encoded-characters-two-level-runtime",
        repo_root=ROOT,
        ranking_policy_path=ranking_policy_path,
    )
    core_dictionary = core_result.tiers[0].dictionary_path

    first_level_dictionary = output_dir / "first_level.dict.yaml"
    first_level_manifest = build_dictionary(
        source=core_dictionary,
        output=first_level_dictionary,
        database=source_database,
        maximum_tier=maximum_tier,
        maximum_length=int(first_level_policy["maximum_text_length"]),
    )
    first_level_character_coverage = _assert_character_boundary(
        first_level_manifest,
        character_policy,
        label="first-level dictionary",
        expected_readings_field="expected_source_reading_entries",
    )
    _write_json(
        output_dir / "first_level.manifest.json",
        first_level_manifest,
    )

    retained_dictionary = output_dir / "retained_long_bridges.dict.yaml"
    retained_manifest = build_dictionary(
        source=core_dictionary,
        output=retained_dictionary,
        database=source_database,
        maximum_tier=maximum_tier,
        maximum_length=64,
    )
    _write_json(
        output_dir / "retained_long_bridges.manifest.json",
        retained_manifest,
    )

    production_export = export_rime_files(
        db_path=source_runtime_database,
        output_dir=output_dir / "production_full",
        mode="full",
        code_form="layout-key",
        schema_id="yime_full",
        schema_name="Yime full source for two-level filtering",
        repo_root=ROOT,
    )

    filtered_dictionary = output_dir / "two_level_full.dict.yaml"
    selection_tsv = output_dir / "selection.tsv"
    dictionary_manifest_path = output_dir / "dictionary.manifest.json"
    dictionary_manifest = build_two_level_dictionary(
        base=first_level_dictionary,
        production=production_export.paths.dict_path,
        output=filtered_dictionary,
        manifest_path=dictionary_manifest_path,
        database=source_database,
        capacity=int(second_level_policy["frequency_cache_capacity"]),
        maximum_tier=maximum_tier,
        minimum_length=int(second_level_policy["minimum_text_length"]),
        retained_long_dictionary=(
            retained_dictionary
            if bool(
                second_level_policy["retain_selected_long_bridges"]
            )
            else None
        ),
        selection_path=selection_tsv,
        ranking_policy_path=ranking_policy_path,
        ranking_capacity_database=capacity_database,
        core_maximum_tier=int(character_policy["core_maximum_tier"]),
        core_weight_offset=int(
            character_ranking_policy["core_weight_offset"]
        ),
        peripheral_weight_offset=int(
            character_ranking_policy["peripheral_weight_offset"]
        ),
        require_core_above_peripheral=bool(
            character_ranking_policy["require_core_above_peripheral"]
        ),
    )
    runtime_character_coverage = _assert_character_boundary(
        dictionary_manifest,
        character_policy,
        label="final two-level dictionary",
        expected_readings_field="expected_runtime_mapping_entries",
    )
    ranking_audit = audit_runtime_ranking_evidence(
        source_database=source_database,
        selection_path=selection_tsv,
        capacity_database=capacity_database,
        policy_path=ranking_policy_path,
    )
    if bool(ranking_gate["require_complete"]) and not (
        ranking_audit.completion_passed
    ):
        raise ValueError(
            "source-separated candidate ranking evidence gate did not pass"
        )
    migration_audit = audit_long_form_core_migration(
        capacity_database=capacity_database,
        input_model_database=input_model_database,
        selection_path=selection_tsv,
        policy_path=policy_path,
    )
    violation_limit = int(
        policy["long_form_core_migration"][
            "selected_runtime_violation_limit"
        ]
    )
    if migration_audit.selected_violations > violation_limit:
        raise ValueError(
            "Two-level selection contains long-form migration candidates: "
            f"{migration_audit.selected_violations} > {violation_limit}"
        )
    coverage_gate = policy["dynamic_coverage_gate"]
    coverage_policy_path = ROOT / str(coverage_gate["policy"])
    dynamic_coverage = evaluate_dynamic_candidate_coverage(
        capacity_database=capacity_database,
        input_model_database=input_model_database,
        selection_path=selection_tsv,
        policy_path=coverage_policy_path,
    )
    if bool(coverage_gate["require_complete"]) and not (
        dynamic_coverage.completion_passed
    ):
        raise ValueError(
            "R0-R5 dynamic candidate coverage gate did not pass"
        )

    filtered_runtime = output_dir / "runtime" / "pinyin_hanzi.db"
    if materialize_runtime_database:
        if filtered_runtime.exists():
            if not reuse_runtime_database:
                raise FileExistsError(
                    f"{filtered_runtime} already exists; pass "
                    "--reuse-runtime-database to reapply the selection "
                    "without replacing its complete inventories"
                )
        else:
            clone_database(source_runtime_database, filtered_runtime)
        runtime_manifest = apply_runtime_selection(
            filtered_runtime,
            selection_tsv,
            manifest_path=output_dir / "runtime.manifest.json",
            strict_unmatched=bool(
                policy["safety"]["unmatched_selected_readings_are_errors"]
            ),
        )
    else:
        runtime_manifest = {
            "status": "skipped",
            "reason": (
                "Windows dictionary handoff does not require a cloned "
                "prototype runtime database"
            ),
        }

    payload = {
        "schema_version": "yime-two-level-runtime-trial-v1",
        "policy": {
            "path": str(policy_path.resolve()),
            "sha256": _sha256(policy_path),
            "policy_id": policy["policy_id"],
        },
        "source_database": str(source_database.resolve()),
        "capacity_database": str(capacity_database.resolve()),
        "input_model_database": str(input_model_database.resolve()),
        "candidate_ranking_evidence": {
            **asdict(ranking_audit),
            "policy": str(ranking_policy_path.resolve()),
            "decision": "pass",
        },
        "long_form_core_migration": {
            **asdict(migration_audit),
            "violation_limit": violation_limit,
            "decision": "pass",
        },
        "dynamic_candidate_coverage": {
            **asdict(dynamic_coverage),
            "policy": str(coverage_policy_path.resolve()),
            "decision": "pass",
        },
        "source_runtime_database": str(
            source_runtime_database.resolve()
        ),
        "character_coverage": {
            "maximum_tier": maximum_tier,
            "core_distinct_characters": int(
                character_policy["core_distinct_characters"]
            ),
            "peripheral_distinct_characters": int(
                character_policy["peripheral_distinct_characters"]
            ),
            "first_level": first_level_character_coverage,
            "runtime": runtime_character_coverage,
            "ranking": dictionary_manifest["single_character_ranking"],
            "decision": "pass",
        },
        "first_level": first_level_manifest,
        "dictionary": dictionary_manifest,
        "runtime": runtime_manifest,
        "outputs": {
            "filtered_dictionary": str(filtered_dictionary.resolve()),
            "selection_tsv": str(selection_tsv.resolve()),
            "filtered_runtime_database": (
                str(filtered_runtime.resolve())
                if materialize_runtime_database
                else ""
            ),
        },
        "run_prototype": {
            "environment_variable": "YIME_RUNTIME_DB_PATH",
            "value": (
                str(filtered_runtime.resolve())
                if materialize_runtime_database
                else ""
            ),
            "available": materialize_runtime_database,
        },
    }
    _write_json(output_dir / "manifest.json", payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument(
        "--source-database",
        type=Path,
        default=DEFAULT_SOURCE,
    )
    parser.add_argument(
        "--capacity-database",
        type=Path,
        default=DEFAULT_CAPACITY,
    )
    parser.add_argument(
        "--source-runtime-database",
        type=Path,
        default=DEFAULT_RUNTIME,
    )
    parser.add_argument(
        "--input-model-database",
        type=Path,
        default=DEFAULT_INPUT_MODEL,
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--reuse-runtime-database",
        action="store_true",
        help=(
            "Reuse an existing cloned runtime database and reapply only "
            "the materialized selection overlay."
        ),
    )
    parser.add_argument(
        "--skip-runtime-database",
        action="store_true",
        help=(
            "Build and validate the Windows handoff dictionary without "
            "cloning or mutating a prototype runtime database."
        ),
    )
    args = parser.parse_args()
    payload = build_trial(
        policy_path=args.policy,
        source_database=args.source_database,
        capacity_database=args.capacity_database,
        input_model_database=args.input_model_database,
        source_runtime_database=args.source_runtime_database,
        output_dir=args.output_dir,
        reuse_runtime_database=args.reuse_runtime_database,
        materialize_runtime_database=not args.skip_runtime_database,
    )
    print(json.dumps(payload, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
