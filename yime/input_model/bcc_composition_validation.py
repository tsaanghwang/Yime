"""Export read-only BCC composition input paths for offline validation."""

from __future__ import annotations

import csv
import heapq
import hashlib
import itertools
import json
import math
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from yime.utils.code_modes import build_code_mode_record, load_ganyin_symbol_metadata
from yime.utils.numeric_pinyin_code import normalize_numeric_pinyin_syllable_spacing
from yime.utils.yinyuan_id_chain import (
    encode_numeric_pinyin_to_yinyuan_ids,
    load_semantic_yinyuan_registry,
    symbol_code_to_yinyuan_ids,
    yinyuan_ids_to_layout_keys,
)

from .recursive_composition import _best_coverage_plans, _materialize_segments


SCHEMA_VERSION = "yime-bcc-composition-path-validation-v1"
PATH_KIND = "component_input_path_not_canonical_whole_string_reading"


@dataclass(frozen=True)
class BccCompositionValidationConfig:
    sample_limit: int = 10
    scan_limit: int = 1_000
    sample_seed: str | None = None
    minimum_target_length: int = 3
    maximum_target_length: int = 12
    maximum_structural_alternatives: int = 128
    maximum_paths_per_target: int = 4_096

    def validate(self) -> None:
        if self.sample_limit < 1:
            raise ValueError("sample_limit must be positive")
        if self.scan_limit < self.sample_limit:
            raise ValueError("scan_limit must be at least sample_limit")
        if self.sample_seed is not None and not self.sample_seed.strip():
            raise ValueError("sample_seed must not be blank")
        if self.minimum_target_length < 2:
            raise ValueError("minimum_target_length must be at least 2")
        if self.maximum_target_length < self.minimum_target_length:
            raise ValueError("maximum_target_length must not be smaller than minimum_target_length")
        if self.maximum_structural_alternatives < 1:
            raise ValueError("maximum_structural_alternatives must be positive")
        if self.maximum_paths_per_target < 1:
            raise ValueError("maximum_paths_per_target must be positive")


@dataclass(frozen=True)
class BccCompositionValidationResult:
    output_dir: Path
    paths_json: Path
    paths_tsv: Path
    manifest: Path
    scanned_count: int
    sample_count: int
    path_count: int
    skipped_count: int


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _open_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    return connection


def _require_columns(
    connection: sqlite3.Connection,
    table: str,
    required: set[str],
) -> None:
    columns = {
        str(row[1])
        for row in connection.execute(f'PRAGMA table_info("{table}")')
    }
    missing = required - columns
    if missing:
        raise ValueError(f"{table} is missing columns: {', '.join(sorted(missing))}")


def _target_rows(
    connection: sqlite3.Connection,
    config: BccCompositionValidationConfig,
) -> list[sqlite3.Row]:
    query = """
        SELECT text, text_length, bcc_frequency, baseline_status,
               baseline_class, baseline_policy, baseline_rule
        FROM candidate_universe
        WHERE has_bcc_evidence = 1
          AND has_gated_reading = 0
          AND text_length BETWEEN ? AND ?
    """
    parameters = (
        config.minimum_target_length,
        config.maximum_target_length,
    )
    if config.sample_seed is None:
        return list(
            connection.execute(
                query + " ORDER BY bcc_frequency DESC, text LIMIT ?",
                (*parameters, config.scan_limit),
            )
        )

    ranked: list[tuple[int, str, sqlite3.Row]] = []
    seed = config.sample_seed.encode("utf-8")
    for row in connection.execute(query, parameters):
        text = str(row["text"])
        rank = int.from_bytes(
            hashlib.sha256(seed + b"\0" + text.encode("utf-8")).digest(),
            "big",
        )
        item = (-rank, text, row)
        if len(ranked) < config.scan_limit:
            heapq.heappush(ranked, item)
        elif item > ranked[0]:
            heapq.heapreplace(ranked, item)
    return [item[2] for item in sorted(ranked, key=lambda item: (-item[0], item[1]))]


def _encoded_substrings(
    source: sqlite3.Connection,
    text: str,
) -> set[str]:
    substrings = {
        text[start:end]
        for start in range(len(text))
        for end in range(start + 1, len(text) + 1)
    }
    placeholders = ", ".join("?" for _ in substrings)
    return {
        str(row[0])
        for row in source.execute(
            f"""
            SELECT DISTINCT text
            FROM canonical_readings
            WHERE text IN ({placeholders})
              AND (LENGTH(text) > 1 OR pronunciation_scope = 'standalone')
            """,
            tuple(sorted(substrings)),
        )
    }


def _readings(
    source: sqlite3.Connection,
    text: str,
) -> tuple[dict[str, Any], ...]:
    scope_clause = "AND pronunciation_scope = 'standalone'" if len(text) == 1 else ""
    return tuple(
        {
            "reading_id": int(row["id"]),
            "marked": str(row["marked_pinyin"]),
            "numeric": str(row["numeric_pinyin"]),
            "is_primary": bool(row["is_primary"]),
            "reading_rank": int(row["reading_rank"]),
            "pinyin_sources": [
                item
                for item in str(row["pinyin_sources"]).split(",")
                if item
            ],
            "source_categories": [
                item
                for item in str(row["reading_source_categories"]).split(",")
                if item
            ],
            "pronunciation_scope": str(row["pronunciation_scope"]),
        }
        for row in source.execute(
            f"""
            SELECT id, marked_pinyin, numeric_pinyin, is_primary,
                   reading_rank, pinyin_sources, reading_source_categories,
                   pronunciation_scope
            FROM canonical_readings
            WHERE text = ? {scope_clause}
            ORDER BY is_primary DESC, reading_rank, id
            """,
            (text,),
        )
    )


def _component_texts(segments: tuple[dict[str, Any], ...]) -> tuple[str, ...] | None:
    components: list[str] = []
    for segment in segments:
        if segment["kind"] == "encoded_multichar":
            components.append(str(segment["text"]))
            continue
        if segment["missing_characters"]:
            return None
        components.extend(str(item) for item in segment["internal_parts"])
    return tuple(components)


def _mode_codes(numeric_input: str) -> dict[str, dict[str, Any]]:
    syllables = normalize_numeric_pinyin_syllable_spacing(numeric_input).split()
    full_ids = tuple(
        yinyuan_id
        for syllable in syllables
        for yinyuan_id in encode_numeric_pinyin_to_yinyuan_ids(syllable)
    )
    registry = load_semantic_yinyuan_registry()
    full_symbols = "".join(registry[yinyuan_id]["runtime_char"] for yinyuan_id in full_ids)
    if symbol_code_to_yinyuan_ids(full_symbols) != full_ids:
        raise RuntimeError("numeric Pinyin to Yinyuan ID chain is inconsistent")
    record = build_code_mode_record(
        full_symbols,
        ganyin_symbol_metadata=load_ganyin_symbol_metadata(),
    )
    result: dict[str, dict[str, Any]] = {}
    for mode, symbols in (
        ("full", record.full_code),
        ("variable", record.variable_code),
        ("shorthand", record.shorthand_code),
    ):
        yinyuan_ids = symbol_code_to_yinyuan_ids(symbols)
        result[mode] = {
            "yinyuan_ids": list(yinyuan_ids),
            "layout_key_code": yinyuan_ids_to_layout_keys(yinyuan_ids),
        }
    return result


def _frequency_by_domain(source: sqlite3.Connection, text: str) -> dict[str, int]:
    available = {
        str(row[1])
        for row in source.execute('PRAGMA table_info("bcc_frequency")')
    }
    domain_columns = [
        column
        for column in (
            "modern_chinese",
            "news",
            "dialogue",
            "literature",
            "classical_chinese",
            "multi_domain",
        )
        if column in available
    ]
    if not domain_columns:
        return {}
    row = source.execute(
        f"SELECT {', '.join(domain_columns)} FROM bcc_frequency WHERE text = ?",
        (text,),
    ).fetchone()
    if row is None:
        return {}
    return {
        key: int(row[key])
        for key in row.keys()
        if row[key] is not None
    }


def _analyze_target(
    source: sqlite3.Connection,
    row: sqlite3.Row,
    config: BccCompositionValidationConfig,
) -> tuple[dict[str, Any] | None, str]:
    text = str(row["text"])
    encoded_texts = _encoded_substrings(source, text)
    coverage = _best_coverage_plans(
        text,
        {item for item in encoded_texts if len(item) >= 2},
        maximum_alternatives=config.maximum_structural_alternatives,
    )
    if coverage.truncated:
        return None, "structural_alternatives_exceed_limit"

    structural_alternatives: list[dict[str, Any]] = []
    path_specs: list[tuple[int, tuple[str, ...], tuple[tuple[dict[str, Any], ...], ...]]] = []
    total_paths = 0
    for index, plan in enumerate(coverage.alternatives):
        segments = _materialize_segments(plan, encoded_texts)
        components = _component_texts(segments)
        if components is None:
            continue
        reading_groups = tuple(_readings(source, component) for component in components)
        if any(not group for group in reading_groups):
            continue
        alternative_path_count = math.prod(len(group) for group in reading_groups)
        total_paths += alternative_path_count
        if total_paths > config.maximum_paths_per_target:
            return None, "reading_paths_exceed_limit"
        structural_alternatives.append(
            {
                "index": index,
                "segments": list(segments),
                "components": list(components),
                "path_count": alternative_path_count,
            }
        )
        path_specs.append((index, components, reading_groups))

    if not path_specs:
        return None, "missing_encoded_component_foundation"

    paths: list[dict[str, Any]] = []
    for structural_index, components, reading_groups in path_specs:
        for reading_path in itertools.product(*reading_groups):
            marked_input = " ".join(str(item["marked"]) for item in reading_path)
            numeric_input = " ".join(str(item["numeric"]) for item in reading_path)
            paths.append(
                {
                    "path_kind": PATH_KIND,
                    "structural_alternative_index": structural_index,
                    "components": [
                        {
                            "text": component,
                            **reading,
                        }
                        for component, reading in zip(components, reading_path, strict=True)
                    ],
                    "marked_component_input": marked_input,
                    "numeric_component_input": numeric_input,
                    "all_component_readings_primary": all(
                        bool(item["is_primary"]) for item in reading_path
                    ),
                    "codes": _mode_codes(numeric_input),
                }
            )

    return {
        "text": text,
        "text_length": int(row["text_length"]),
        "bcc_frequency": int(row["bcc_frequency"]),
        "bcc_frequency_by_domain": _frequency_by_domain(source, text),
        "target_has_gated_reading": False,
        "candidate_disposition": {
            "status": str(row["baseline_status"]),
            "class": str(row["baseline_class"]),
            "policy": str(row["baseline_policy"]),
            "rule": str(row["baseline_rule"]),
            "changed_by_validation": False,
        },
        "structural_ambiguous": len(structural_alternatives) > 1,
        "reading_ambiguous": len(paths) > len(structural_alternatives),
        "structural_alternatives": structural_alternatives,
        "composition_input_path_count": len(paths),
        "composition_input_paths": paths,
    }, ""


def _write_tsv(samples: list[dict[str, Any]], path: Path) -> None:
    fields = (
        "text",
        "bcc_frequency",
        "structural_alternative_index",
        "components_json",
        "marked_component_input",
        "numeric_component_input",
        "full_layout_key_code",
        "variable_layout_key_code",
        "shorthand_layout_key_code",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for sample in samples:
            for item in sample["composition_input_paths"]:
                writer.writerow(
                    {
                        "text": sample["text"],
                        "bcc_frequency": sample["bcc_frequency"],
                        "structural_alternative_index": item["structural_alternative_index"],
                        "components_json": json.dumps(item["components"], ensure_ascii=False),
                        "marked_component_input": item["marked_component_input"],
                        "numeric_component_input": item["numeric_component_input"],
                        "full_layout_key_code": item["codes"]["full"]["layout_key_code"],
                        "variable_layout_key_code": item["codes"]["variable"]["layout_key_code"],
                        "shorthand_layout_key_code": item["codes"]["shorthand"]["layout_key_code"],
                    }
                )


def validate_bcc_composition_paths(
    *,
    source_database: Path,
    input_model_database: Path,
    output_dir: Path,
    config: BccCompositionValidationConfig = BccCompositionValidationConfig(),
) -> BccCompositionValidationResult:
    """Export complete path alternatives for a small sample without writing inputs."""

    config.validate()
    source_database = source_database.resolve()
    input_model_database = input_model_database.resolve()
    output_dir = output_dir.resolve()
    for path in (source_database, input_model_database):
        if not path.is_file():
            raise FileNotFoundError(path)

    input_identity = {
        "source_database": {
            "path": str(source_database),
            "bytes": source_database.stat().st_size,
            "sha256": _sha256(source_database),
        },
        "input_model_database": {
            "path": str(input_model_database),
            "bytes": input_model_database.stat().st_size,
            "sha256": _sha256(input_model_database),
        },
    }
    input_stats_before = {
        path: (path.stat().st_size, path.stat().st_mtime_ns)
        for path in (source_database, input_model_database)
    }

    with _open_read_only(source_database) as source, _open_read_only(
        input_model_database
    ) as input_model:
        _require_columns(
            source,
            "canonical_readings",
            {
                "id",
                "text",
                "marked_pinyin",
                "numeric_pinyin",
                "reading_rank",
                "is_primary",
                "pinyin_sources",
                "reading_source_categories",
                "pronunciation_scope",
            },
        )
        _require_columns(
            input_model,
            "candidate_universe",
            {
                "text",
                "text_length",
                "bcc_frequency",
                "has_bcc_evidence",
                "has_gated_reading",
                "baseline_status",
                "baseline_class",
                "baseline_policy",
                "baseline_rule",
            },
        )
        rows = _target_rows(input_model, config)
        samples: list[dict[str, Any]] = []
        skipped: list[dict[str, Any]] = []
        scanned_count = 0
        for row in rows:
            scanned_count += 1
            sample, reason = _analyze_target(source, row, config)
            if sample is None:
                skipped.append({"text": str(row["text"]), "reason": reason})
                continue
            samples.append(sample)
            if len(samples) >= config.sample_limit:
                break

    input_stats_after = {
        path: (path.stat().st_size, path.stat().st_mtime_ns)
        for path in (source_database, input_model_database)
    }
    if input_stats_after != input_stats_before:
        raise RuntimeError("an input database changed during read-only validation")

    output_dir.mkdir(parents=True, exist_ok=True)
    paths_json = output_dir / "composition_input_paths.json"
    paths_tsv = output_dir / "composition_input_paths.tsv"
    manifest_path = output_dir / "manifest.json"
    payload = {
        "schema_version": SCHEMA_VERSION,
        "semantics": {
            "path_kind": PATH_KIND,
            "bcc_is_frequency_evidence_only": True,
            "component_readings_are_source_gated": True,
            "target_whole_string_reading_is_not_created": True,
            "target_candidate_disposition_is_not_changed": True,
            "runtime_or_user_candidate_imported": False,
            "input_databases_opened_read_only": True,
            "reported_targets_include_all_paths": True,
            "over_limit_targets_are_skipped_not_truncated": True,
            "seeded_sampling_is_content_deterministic": config.sample_seed is not None,
        },
        "config": asdict(config),
        "samples": samples,
        "skipped": skipped,
    }
    paths_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    _write_tsv(samples, paths_tsv)
    path_count = sum(int(item["composition_input_path_count"]) for item in samples)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "inputs": input_identity,
        "input_databases_unchanged": True,
        "outputs": {
            "composition_input_paths_json": {
                "path": str(paths_json),
                "sha256": _sha256(paths_json),
            },
            "composition_input_paths_tsv": {
                "path": str(paths_tsv),
                "sha256": _sha256(paths_tsv),
            },
        },
        "counts": {
            "scanned": scanned_count,
            "samples": len(samples),
            "paths": path_count,
            "skipped": len(skipped),
        },
        "semantics": payload["semantics"],
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return BccCompositionValidationResult(
        output_dir=output_dir,
        paths_json=paths_json,
        paths_tsv=paths_tsv,
        manifest=manifest_path,
        scanned_count=scanned_count,
        sample_count=len(samples),
        path_count=path_count,
        skipped_count=len(skipped),
    )


__all__ = [
    "BccCompositionValidationConfig",
    "BccCompositionValidationResult",
    "validate_bcc_composition_paths",
]
