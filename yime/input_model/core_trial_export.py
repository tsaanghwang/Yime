"""Export compact, replay-gated Yime dictionaries from a capacity proposal.

The capacity model selects texts, while this exporter preserves every accepted
reading of each selected text.  Codes are always derived from the repository's
canonical syllable pipeline and unique keyboard-layout projection.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import sqlite3
from collections import Counter
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterable, Mapping

from yime.canonical_yime_mapping import load_canonical_code_map
from yime.utils.numeric_pinyin_code import (
    resolve_canonical_code_from_numeric_pinyin,
)
from yime.input_model.ranking_evidence import (
    DEFAULT_POLICY_PATH as DEFAULT_RANKING_POLICY_PATH,
    build_ranking_calibration,
    calibration_summary,
    resolve_ranking_evidence,
)
from yime.utils.rime_export import (
    convert_runtime_code_to_layout_keys,
    load_runtime_symbol_to_layout_key,
)
from yime.utils.yinyuan_id_chain import layout_projection_digest


SCHEMA_VERSION = "yime-core-trial-lexicon-v1"
SOURCE_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9_-]*$")


@dataclass(frozen=True)
class CoreTrialTierResult:
    capacity: int
    selected_texts: int
    reading_entries: int
    dictionary_path: Path
    selection_path: Path
    manifest_path: Path


@dataclass(frozen=True)
class CoreTrialExportResult:
    output_dir: Path
    mandatory_capacity: int
    recommended_capacity: int
    tiers: tuple[CoreTrialTierResult, ...]
    index_manifest: Path


def _file_identity(path: Path) -> dict[str, object]:
    stat = path.stat()
    return {
        "path": str(path.resolve()),
        "size": stat.st_size,
        "modified_ns": stat.st_mtime_ns,
    }


def _small_file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_capacity_metadata(
    capacity_database: Path,
) -> tuple[int, int, int]:
    with sqlite3.connect(capacity_database) as connection:
        mandatory = int(
            connection.execute(
                "SELECT COUNT(*) FROM static_capacity_items "
                "WHERE mandatory_static = 1"
            ).fetchone()[0]
        )
        total = int(
            connection.execute(
                "SELECT COUNT(*) FROM static_capacity_items"
            ).fetchone()[0]
        )
        metadata = dict(connection.execute("SELECT key, value FROM metadata"))
    recommended = int(metadata.get("recommended_static_capacity", mandatory))
    return mandatory, recommended, total


def default_core_trial_capacities(
    *,
    mandatory_capacity: int,
    recommended_capacity: int,
    total_texts: int,
) -> tuple[int, ...]:
    values = (
        mandatory_capacity,
        mandatory_capacity + 10_000,
        mandatory_capacity + 50_000,
        recommended_capacity,
        mandatory_capacity + 100_000,
        mandatory_capacity + 150_000,
    )
    return tuple(sorted({min(total_texts, value) for value in values}))


def _normalize_capacities(
    capacities: Iterable[int],
    *,
    mandatory_capacity: int,
    total_texts: int,
) -> tuple[int, ...]:
    normalized = tuple(sorted({int(value) for value in capacities}))
    if not normalized:
        raise ValueError("At least one core-trial capacity is required")
    for value in normalized:
        if value < mandatory_capacity:
            raise ValueError(
                f"Capacity {value} is below mandatory base "
                f"{mandatory_capacity}"
            )
        if value > total_texts:
            raise ValueError(
                f"Capacity {value} exceeds encoded text count {total_texts}"
            )
    return normalized


def _source_columns(
    connection: sqlite3.Connection,
) -> set[str]:
    return {
        str(row[1])
        for row in connection.execute(
            "PRAGMA source.table_info(canonical_readings)"
        )
    }


def _selected_readings(
    capacity_database: Path,
    source_database: Path,
    selected_optional_texts: int,
    included_pinyin_sources: tuple[str, ...],
    included_source_lengths: Mapping[str, tuple[int, ...]],
    included_wanxiang_category_lengths: Mapping[str, tuple[int, ...]],
) -> list[sqlite3.Row]:
    connection = sqlite3.connect(capacity_database)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            "ATTACH DATABASE ? AS source",
            (str(source_database.resolve()),),
        )
        columns = _source_columns(connection)
        if "pronunciation_scope" not in columns:
            raise ValueError(
                "Source canonical_readings has no pronunciation_scope column"
            )
        wanxiang_expr = (
            "COALESCE(r.wanxiang_weight, 0)"
            if "wanxiang_weight" in columns
            else "0"
        )
        wanxiang_categories_expr = (
            "r.wanxiang_categories"
            if "wanxiang_categories" in columns
            else "''"
        )
        if (
            included_wanxiang_category_lengths
            and "wanxiang_categories" not in columns
        ):
            raise ValueError(
                "Source canonical_readings has no wanxiang_categories column"
            )
        source_predicates = [
            "instr(',' || r.pinyin_sources || ',', ',' || ? || ',') > 0"
            for _ in included_pinyin_sources
        ]
        selection_parameters: list[object] = [
            selected_optional_texts,
            *included_pinyin_sources,
        ]
        for source_name, lengths in included_source_lengths.items():
            placeholders = ", ".join("?" for _ in lengths)
            source_predicates.append(
                "("
                "instr(',' || r.pinyin_sources || ',', ',' || ? || ',') > 0 "
                f"AND i.text_length IN ({placeholders})"
                ")"
            )
            selection_parameters.extend((source_name, *lengths))
        for category, lengths in included_wanxiang_category_lengths.items():
            placeholders = ", ".join("?" for _ in lengths)
            source_predicates.append(
                "("
                "instr(',' || r.pinyin_sources || ',', ',wanxiang,') > 0 "
                "AND instr(',' || r.wanxiang_categories || ',', "
                "',' || ? || ',') > 0 "
                f"AND i.text_length IN ({placeholders})"
                ")"
            )
            selection_parameters.extend((category, *lengths))
        selection_predicate = (
            "(i.mandatory_static = 1 OR o.selection_rank <= ?)"
        )
        if source_predicates:
            selection_predicate += " OR " + " OR ".join(source_predicates)
        return connection.execute(
            f"""
            SELECT
                r.text,
                r.numeric_pinyin,
                r.reading_rank,
                r.is_primary,
                r.bcc_frequency,
                {wanxiang_expr} AS wanxiang_weight,
                i.text_length,
                i.mandatory_static,
                COALESCE(o.selection_rank, 0) AS selection_rank,
                i.mandatory_reasons,
                i.utility_score,
                r.pinyin_sources,
                {wanxiang_categories_expr} AS wanxiang_categories
            FROM source.canonical_readings AS r
            JOIN static_capacity_items AS i
              ON i.text = r.text
            LEFT JOIN optional_static_rank AS o
              ON o.text = r.text
            WHERE ({selection_predicate})
              AND (
                    i.text_length > 1
                    OR r.pronunciation_scope = 'standalone'
                  )
            ORDER BY
                i.mandatory_static DESC,
                COALESCE(o.selection_rank, 0),
                r.text,
                r.reading_rank,
                r.numeric_pinyin
            """,
            selection_parameters,
        ).fetchall()
    finally:
        connection.close()


def _dictionary_text(
    *,
    dictionary_name: str,
    capacity: int,
    entries: list[tuple[str, str, int]],
) -> str:
    lines = [
        "# Rime dictionary",
        "# encoding: utf-8",
        "# Experimental compact component lexicon; replay gate required.",
        "---",
        f"name: {dictionary_name}",
        f'version: "{date.today().isoformat()}"',
        "sort: by_weight",
        "use_preset_vocabulary: false",
        "...",
    ]
    lines.extend(f"{text}\t{code}\t{weight}" for text, code, weight in entries)
    lines.append("")
    return "\n".join(lines)


def export_core_trial_lexicons(
    *,
    source_database: Path,
    capacity_database: Path,
    output_dir: Path,
    capacities: Iterable[int] | None = None,
    include_pinyin_sources: Iterable[str] = (),
    include_source_lengths: Mapping[str, Iterable[int]] | None = None,
    include_wanxiang_category_lengths: (
        Mapping[str, Iterable[int]] | None
    ) = None,
    trial_label: str = "",
    repo_root: Path,
    ranking_policy_path: Path = DEFAULT_RANKING_POLICY_PATH,
) -> CoreTrialExportResult:
    """Export fixed-length canonical dictionaries for selected capacity tiers."""

    if not source_database.is_file():
        raise FileNotFoundError(source_database)
    if not capacity_database.is_file():
        raise FileNotFoundError(capacity_database)

    mandatory, recommended, total = _load_capacity_metadata(
        capacity_database
    )
    selected_capacities = _normalize_capacities(
        capacities
        if capacities is not None
        else default_core_trial_capacities(
            mandatory_capacity=mandatory,
            recommended_capacity=recommended,
            total_texts=total,
        ),
        mandatory_capacity=mandatory,
        total_texts=total,
    )
    included_sources = tuple(
        sorted({str(item).strip() for item in include_pinyin_sources if str(item).strip()})
    )
    invalid_sources = [
        item for item in included_sources if not SOURCE_NAME_PATTERN.fullmatch(item)
    ]
    if invalid_sources:
        raise ValueError(
            "Invalid pinyin source name(s): " + ", ".join(invalid_sources)
        )
    included_lengths = {
        str(source).strip(): tuple(
            sorted({int(length) for length in lengths})
        )
        for source, lengths in (include_source_lengths or {}).items()
    }
    invalid_length_sources = [
        source
        for source in included_lengths
        if not SOURCE_NAME_PATTERN.fullmatch(source)
    ]
    if invalid_length_sources:
        raise ValueError(
            "Invalid length-filtered pinyin source name(s): "
            + ", ".join(invalid_length_sources)
        )
    empty_length_sources = [
        source for source, lengths in included_lengths.items() if not lengths
    ]
    if empty_length_sources:
        raise ValueError(
            "No text lengths supplied for source(s): "
            + ", ".join(empty_length_sources)
        )
    invalid_lengths = sorted(
        {
            length
            for lengths in included_lengths.values()
            for length in lengths
            if length <= 0
        }
    )
    if invalid_lengths:
        raise ValueError(
            "Text lengths must be positive: "
            + ", ".join(str(item) for item in invalid_lengths)
        )
    included_wanxiang_categories = {
        str(category).strip(): tuple(
            sorted({int(length) for length in lengths})
        )
        for category, lengths in (
            include_wanxiang_category_lengths or {}
        ).items()
    }
    invalid_categories = [
        category
        for category in included_wanxiang_categories
        if not SOURCE_NAME_PATTERN.fullmatch(category)
    ]
    if invalid_categories:
        raise ValueError(
            "Invalid Wanxiang category name(s): "
            + ", ".join(invalid_categories)
        )
    empty_categories = [
        category
        for category, lengths in included_wanxiang_categories.items()
        if not lengths
    ]
    if empty_categories:
        raise ValueError(
            "No text lengths supplied for Wanxiang category/categories: "
            + ", ".join(empty_categories)
        )
    invalid_category_lengths = sorted(
        {
            length
            for lengths in included_wanxiang_categories.values()
            for length in lengths
            if length <= 0
        }
    )
    if invalid_category_lengths:
        raise ValueError(
            "Wanxiang category text lengths must be positive: "
            + ", ".join(str(item) for item in invalid_category_lengths)
        )
    normalized_label = trial_label.strip()
    if normalized_label and not SOURCE_NAME_PATTERN.fullmatch(normalized_label):
        raise ValueError(f"Invalid trial label: {normalized_label}")

    output_dir.mkdir(parents=True, exist_ok=True)
    ranking_calibration = build_ranking_calibration(
        source_database=source_database,
        capacity_database=capacity_database,
        policy_path=ranking_policy_path,
    )
    pinyin_to_runtime_code = load_canonical_code_map(repo_root)
    symbol_to_key = load_runtime_symbol_to_layout_key(repo_root)
    layout_digest = layout_projection_digest(repo_root)
    results: list[CoreTrialTierResult] = []

    for capacity in selected_capacities:
        rows = _selected_readings(
            capacity_database,
            source_database,
            capacity - mandatory,
            included_sources,
            included_lengths,
            included_wanxiang_categories,
        )
        if normalized_label:
            source_suffix = "_plus_" + normalized_label.replace("-", "_")
        elif included_sources:
            source_suffix = "_plus_" + "_".join(included_sources)
        elif included_lengths or included_wanxiang_categories:
            source_suffix = "_plus_scoped_sources"
        else:
            source_suffix = ""
        tier_dir = output_dir / f"capacity_{capacity:07d}{source_suffix}"
        tier_dir.mkdir(parents=True, exist_ok=True)
        dictionary_name = f"yime_core_{capacity:07d}{source_suffix}_full"
        dictionary_path = tier_dir / f"{dictionary_name}.dict.yaml"
        selection_path = tier_dir / "selection.tsv"
        manifest_path = tier_dir / "manifest.json"

        entries: list[tuple[str, str, int]] = []
        selected_texts: set[str] = set()
        ranking_evidence_readings: Counter[str] = Counter()
        ranking_evidence_texts: dict[str, set[str]] = {}
        with selection_path.open(
            "w",
            encoding="utf-8",
            newline="",
        ) as stream:
            writer = csv.writer(
                stream,
                delimiter="\t",
                lineterminator="\n",
            )
            writer.writerow(
                (
                    "text",
                    "numeric_pinyin",
                    "full_layout_code",
                    "weight",
                    "bcc_frequency",
                    "wanxiang_weight",
                    "ranking_evidence_source",
                    "ranking_evidence_status",
                    "normalized_fallback_percentile",
                    "normalized_structural_percentile",
                    "ranking_evidence_provisional",
                    "requires_independent_corpus",
                    "mandatory_static",
                    "selection_rank",
                    "mandatory_reasons",
                    "utility_score",
                    "pinyin_sources",
                    "selection_reasons",
                )
            )
            for row in rows:
                numeric_pinyin = str(row["numeric_pinyin"] or "").strip()
                runtime_code = resolve_canonical_code_from_numeric_pinyin(
                    pinyin_to_runtime_code,
                    numeric_pinyin,
                )
                if not runtime_code:
                    raise ValueError(
                        "Accepted reading cannot be encoded by the formal "
                        f"syllable chain: {row['text']} / {numeric_pinyin}"
                    )
                full_layout_code = convert_runtime_code_to_layout_keys(
                    runtime_code,
                    symbol_to_key,
                )
                syllable_count = len(numeric_pinyin.split())
                if len(full_layout_code) != 4 * syllable_count:
                    raise ValueError(
                        "Full code is not four Yinyuan positions per syllable: "
                        f"{row['text']} / {numeric_pinyin} / "
                        f"{full_layout_code}"
                    )
                ranking = resolve_ranking_evidence(
                    row,
                    ranking_calibration,
                )
                weight = ranking.effective_weight
                text = str(row["text"])
                selected_texts.add(text)
                ranking_evidence_readings[ranking.evidence_source] += 1
                ranking_evidence_texts.setdefault(
                    ranking.evidence_source,
                    set(),
                ).add(text)
                entries.append((text, full_layout_code, weight))
                selection_reasons: list[str] = []
                if int(row["mandatory_static"]):
                    selection_reasons.append("mandatory_static")
                elif int(row["selection_rank"]) <= capacity - mandatory:
                    selection_reasons.append("capacity_rank")
                row_sources = {
                    item
                    for item in str(row["pinyin_sources"]).split(",")
                    if item
                }
                selection_reasons.extend(
                    f"source:{item}"
                    for item in included_sources
                    if item in row_sources
                )
                text_length = int(row["text_length"])
                selection_reasons.extend(
                    f"source:{source_name}:length:{text_length}"
                    for source_name, lengths in included_lengths.items()
                    if source_name in row_sources and text_length in lengths
                )
                row_wanxiang_categories = {
                    item
                    for item in str(row["wanxiang_categories"]).split(",")
                    if item
                }
                selection_reasons.extend(
                    f"wanxiang_category:{category}:length:{text_length}"
                    for category, lengths in (
                        included_wanxiang_categories.items()
                    )
                    if category in row_wanxiang_categories
                    and text_length in lengths
                )
                writer.writerow(
                    (
                        text,
                        numeric_pinyin,
                        full_layout_code,
                        weight,
                        ranking.bcc_frequency,
                        ranking.wanxiang_weight,
                        ranking.evidence_source,
                        ranking.evidence_status,
                        (
                            f"{ranking.normalized_fallback_percentile:.9f}"
                        ),
                        (
                            f"{ranking.normalized_structural_percentile:.9f}"
                        ),
                        int(ranking.provisional),
                        int(ranking.requires_independent_corpus),
                        int(row["mandatory_static"]),
                        int(row["selection_rank"]),
                        str(row["mandatory_reasons"]),
                        float(row["utility_score"]),
                        str(row["pinyin_sources"]),
                        ",".join(selection_reasons),
                    )
                )

        if (
            not included_sources
            and not included_lengths
            and not included_wanxiang_categories
            and len(selected_texts) != capacity
        ):
            raise ValueError(
                f"Capacity selection mismatch: expected {capacity} texts, "
                f"got {len(selected_texts)}"
            )
        if len(selected_texts) < capacity:
            raise ValueError(
                f"Expanded selection lost base capacity: expected at least "
                f"{capacity} texts, got {len(selected_texts)}"
            )
        dictionary_path.write_text(
            _dictionary_text(
                dictionary_name=dictionary_name,
                capacity=capacity,
                entries=entries,
            ),
            encoding="utf-8",
        )
        manifest = {
            "schema_version": SCHEMA_VERSION,
            "trial_only": True,
            "runtime_replay_required": True,
            "dictionary_name": dictionary_name,
            "capacity_unit": "distinct_text",
            "base_capacity": capacity,
            "selected_texts": len(selected_texts),
            "reading_entries": len(entries),
            "mandatory_static_texts": mandatory,
            "selected_optional_texts": capacity - mandatory,
            "included_pinyin_sources": list(included_sources),
            "included_source_lengths": {
                source: list(lengths)
                for source, lengths in included_lengths.items()
            },
            "included_wanxiang_category_lengths": {
                category: list(lengths)
                for category, lengths in (
                    included_wanxiang_categories.items()
                )
            },
            "trial_label": normalized_label,
            "recommended_capacity": recommended,
            "ranking_evidence": {
                **calibration_summary(ranking_calibration),
                "policy_sha256": _small_file_sha256(ranking_policy_path),
                "reading_entries_by_source": dict(
                    sorted(ranking_evidence_readings.items())
                ),
                "distinct_texts_by_source": {
                    source: len(texts)
                    for source, texts in sorted(
                        ranking_evidence_texts.items()
                    )
                },
                "raw_bcc_and_lmdg_values_added": False,
            },
            "full_code_form": "canonical_layout_key",
            "layout_projection_sha256": layout_digest,
            "source_database": _file_identity(source_database),
            "capacity_database": _file_identity(capacity_database),
            "outputs": {
                "dictionary": dictionary_path.name,
                "dictionary_sha256": _small_file_sha256(dictionary_path),
                "selection": selection_path.name,
                "selection_sha256": _small_file_sha256(selection_path),
            },
        }
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        results.append(
            CoreTrialTierResult(
                capacity=capacity,
                selected_texts=len(selected_texts),
                reading_entries=len(entries),
                dictionary_path=dictionary_path,
                selection_path=selection_path,
                manifest_path=manifest_path,
            )
        )

    index_manifest = output_dir / "manifest.json"
    capacity_manifest = capacity_database.parent / "manifest.json"
    source_manifest = source_database.parent / "manifest.json"
    index = {
        "schema_version": SCHEMA_VERSION,
        "trial_only": True,
        "runtime_replay_required": True,
        "mandatory_capacity": mandatory,
        "recommended_capacity": recommended,
        "encoded_texts": total,
        "capacities": list(selected_capacities),
        "included_pinyin_sources": list(included_sources),
        "included_source_lengths": {
            source: list(lengths)
            for source, lengths in included_lengths.items()
        },
        "included_wanxiang_category_lengths": {
            category: list(lengths)
            for category, lengths in included_wanxiang_categories.items()
        },
        "trial_label": normalized_label,
        "ranking_evidence": {
            **calibration_summary(ranking_calibration),
            "policy_sha256": _small_file_sha256(ranking_policy_path),
            "raw_bcc_and_lmdg_values_added": False,
        },
        "layout_projection_sha256": layout_digest,
        "capacity_model_manifest_sha256": (
            _small_file_sha256(capacity_manifest)
            if capacity_manifest.is_file()
            else ""
        ),
        "source_bundle_manifest_sha256": (
            _small_file_sha256(source_manifest)
            if source_manifest.is_file()
            else ""
        ),
        "tiers": [
            {
                "capacity": item.capacity,
                "selected_texts": item.selected_texts,
                "reading_entries": item.reading_entries,
                "directory": item.dictionary_path.parent.name,
                "dictionary": item.dictionary_path.name,
            }
            for item in results
        ],
    }
    index_manifest.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return CoreTrialExportResult(
        output_dir=output_dir,
        mandatory_capacity=mandatory,
        recommended_capacity=recommended,
        tiers=tuple(results),
        index_manifest=index_manifest,
    )
