"""Prove unencoded strings reachable from shorter source-gated strings.

This model is evidence-only.  It composes an input sequence from attested
component readings, but never promotes that sequence to a source reading for
the whole target and never changes the target's review disposition.
"""

from __future__ import annotations

import csv
import json
import math
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

from .store import InputModelStore


MODEL_VERSION = "yime-recursive-unencoded-composition-v2"
EVIDENCE_RULE = "shorter_gated_string_recursive_composition"


@dataclass(frozen=True)
class RecursiveCompositionConfig:
    minimum_target_length: int = 2
    maximum_alternatives: int = 4
    maximum_parts_per_step: int = 6
    maximum_component_readings: int = 4

    def validate(self) -> None:
        if self.minimum_target_length < 2:
            raise ValueError("minimum_target_length must be at least 2")
        if self.maximum_alternatives < 1:
            raise ValueError("maximum_alternatives must be positive")
        if self.maximum_parts_per_step < 2:
            raise ValueError("maximum_parts_per_step must be at least 2")
        if self.maximum_component_readings < 1:
            raise ValueError("maximum_component_readings must be positive")


@dataclass(frozen=True)
class RecursiveCompositionResult:
    input_model_database: Path
    output_dir: Path
    evidence_tsv: Path
    summary_markdown: Path
    manifest: Path
    target_count: int
    reachable_count: int
    unreachable_count: int
    structurally_ambiguous_count: int
    reading_ambiguous_count: int
    uses_multichar_component_count: int
    residual_blocks_only_count: int
    single_exception_target_count: int


@dataclass(frozen=True)
class _CoveragePlan:
    count: int
    alternatives: tuple[tuple[tuple[str, str], ...], ...]
    truncated: bool


def _coverage_key(
    segments: tuple[tuple[str, str], ...],
) -> tuple[object, ...]:
    residuals = tuple(
        text for kind, text in segments if kind == "residual"
    )
    encoded = tuple(
        text for kind, text in segments if kind == "encoded_multichar"
    )
    return (
        sum(len(text) == 1 for text in residuals),
        sum(len(text) for text in residuals),
        len(encoded),
        tuple(sorted(-len(text) for text in encoded)),
        tuple(-len(text) for text in encoded),
    )


def _best_coverage_plans(
    text: str,
    encoded_texts: set[str],
    *,
    maximum_alternatives: int,
) -> _CoveragePlan:
    """Prefer encoded multi-character coverage without exposing single leaves."""

    memo: dict[int, _CoveragePlan] = {}

    def visit(offset: int) -> _CoveragePlan:
        if offset == len(text):
            return _CoveragePlan(1, ((),), False)
        if offset in memo:
            return memo[offset]

        candidates: list[
            tuple[
                tuple[object, ...],
                bool,
                tuple[tuple[str, str], ...],
            ]
        ] = []
        suffix = visit(offset + 1)
        for alternative in suffix.alternatives:
            if alternative and alternative[0][0] == "residual":
                residual = (
                    "residual",
                    text[offset] + alternative[0][1],
                )
                plan = (residual, *alternative[1:])
            else:
                plan = (("residual", text[offset]), *alternative)
            candidates.append((_coverage_key(plan), suffix.truncated, plan))

        for end in range(len(text), offset + 1, -1):
            part = text[offset:end]
            if part not in encoded_texts:
                continue
            suffix = visit(end)
            for alternative in suffix.alternatives:
                plan = (("encoded_multichar", part), *alternative)
                candidates.append((_coverage_key(plan), suffix.truncated, plan))

        best_key = min(item[0] for item in candidates)
        samples: set[tuple[tuple[str, str], ...]] = set()
        inherited_truncation = False
        for key, truncated, plan in candidates:
            if key != best_key:
                continue
            samples.add(plan)
            inherited_truncation = inherited_truncation or truncated
        best_count = len(samples)
        truncated = (
            inherited_truncation or best_count > maximum_alternatives
        )
        alternatives = tuple(
            sorted(
                samples,
                key=lambda plan: (_coverage_key(plan), plan),
            )[:maximum_alternatives]
        )
        result = _CoveragePlan(best_count, alternatives, truncated)
        memo[offset] = result
        return result

    return visit(0)


def _default_residual_blocks(text: str) -> tuple[str, ...]:
    if len(text) <= 1:
        return (text,)
    blocks: list[str] = []
    offset = 0
    while len(text) - offset > 3:
        blocks.append(text[offset : offset + 2])
        offset += 2
    blocks.append(text[offset:])
    return tuple(blocks)


def _absorb_single_residuals(
    plan: tuple[tuple[str, str], ...],
) -> tuple[tuple[str, str], ...]:
    """Turn every exposed residual character into a neighbouring residual run."""

    segments = list(plan)
    offset = 0
    while offset < len(segments):
        kind, text = segments[offset]
        if kind != "residual" or len(text) != 1:
            offset += 1
            continue
        if len(segments) == 1:
            return tuple(segments)
        use_left = offset > 0 and (
            offset == len(segments) - 1
            or len(segments[offset - 1][1])
            <= len(segments[offset + 1][1])
        )
        if use_left:
            combined = segments[offset - 1][1] + text
            segments[offset - 1 : offset + 1] = [("residual", combined)]
            offset = max(0, offset - 1)
        else:
            combined = text + segments[offset + 1][1]
            segments[offset : offset + 2] = [("residual", combined)]
    return tuple(segments)


def _best_leaf_parts(
    text: str,
    all_encoded_texts: set[str],
) -> tuple[str, ...] | None:
    memo: dict[int, tuple[str, ...] | None] = {}

    def visit(offset: int) -> tuple[str, ...] | None:
        if offset == len(text):
            return ()
        if offset in memo:
            return memo[offset]
        candidates: list[tuple[str, ...]] = []
        for end in range(len(text), offset, -1):
            part = text[offset:end]
            if part not in all_encoded_texts:
                continue
            suffix = visit(end)
            if suffix is not None:
                candidates.append((part, *suffix))
        if not candidates:
            memo[offset] = None
        else:
            memo[offset] = min(
                candidates,
                key=lambda parts: (
                    len(parts),
                    tuple(-len(part) for part in parts),
                    parts,
                ),
            )
        return memo[offset]

    return visit(0)


def _residual_blocks(
    text: str,
    all_encoded_texts: set[str],
) -> tuple[str, ...]:
    default_blocks = _default_residual_blocks(text)
    if len(text) != 4:
        return default_blocks
    whole_parts = _best_leaf_parts(text, all_encoded_texts)
    pair_parts = [
        _best_leaf_parts(block, all_encoded_texts)
        for block in default_blocks
    ]
    whole_coverage = sum(
        len(part)
        for part in (whole_parts or ())
        if len(part) >= 2
    )
    pair_coverage = sum(
        len(part)
        for parts in pair_parts
        for part in (parts or ())
        if len(part) >= 2
    )
    return (text,) if whole_coverage > pair_coverage else default_blocks


def _materialize_segments(
    plan: tuple[tuple[str, str], ...],
    all_encoded_texts: set[str],
) -> tuple[dict[str, Any], ...]:
    segments: list[dict[str, Any]] = []
    for kind, text in _absorb_single_residuals(plan):
        if kind == "encoded_multichar":
            segments.append({"kind": kind, "text": text})
            continue
        for block in _residual_blocks(text, all_encoded_texts):
            internal_parts = _best_leaf_parts(block, all_encoded_texts)
            missing_characters = [
                character
                for character in block
                if character not in all_encoded_texts
            ]
            segments.append(
                {
                    "kind": "dynamic_residual_block",
                    "text": block,
                    "fallback_size": len(block),
                    "internal_parts": (
                        list(internal_parts)
                        if internal_parts is not None
                        else []
                    ),
                    "missing_characters": list(
                        dict.fromkeys(missing_characters)
                    ),
                }
            )
    return tuple(segments)


def build_composition_tree(
    components: list[dict[str, Any]],
    *,
    maximum_parts_per_step: int,
) -> tuple[dict[str, Any], int]:
    nodes = [
        {
            "kind": str(item.get("kind", "encoded_component")),
            "text": item["text"],
            "reading_id": item["primary"]["reading_id"],
            "marked": item["primary"]["marked"],
            "numeric": item["primary"]["numeric"],
            "depth": 0,
        }
        for item in components
    ]
    while len(nodes) > 1:
        next_nodes: list[dict[str, Any]] = []
        for offset in range(0, len(nodes), maximum_parts_per_step):
            children = nodes[offset : offset + maximum_parts_per_step]
            if len(children) == 1:
                next_nodes.append(children[0])
                continue
            next_nodes.append(
                {
                    "kind": "dynamic_composition",
                    "text": "".join(str(child["text"]) for child in children),
                    "children": children,
                    "marked_input": " ".join(
                        str(child.get("marked", child.get("marked_input", "")))
                        for child in children
                    ).strip(),
                    "numeric_input": " ".join(
                        str(child.get("numeric", child.get("numeric_input", "")))
                        for child in children
                    ).strip(),
                    "depth": max(int(child["depth"]) for child in children) + 1,
                }
            )
        nodes = next_nodes
    return nodes[0], int(nodes[0]["depth"])


def _blocker(text: str, encoded_texts: set[str]) -> dict[str, Any]:
    reachable_offsets = {0}
    for offset in range(len(text)):
        if offset not in reachable_offsets:
            continue
        for end in range(len(text), offset, -1):
            if text[offset:end] in encoded_texts:
                reachable_offsets.add(end)
    furthest = max(reachable_offsets)

    reverse_offsets = {len(text)}
    for end in range(len(text), 0, -1):
        if end not in reverse_offsets:
            continue
        for offset in range(0, end):
            if text[offset:end] in encoded_texts:
                reverse_offsets.add(offset)
    earliest_suffix = min(reverse_offsets)
    missing_characters = tuple(
        dict.fromkeys(character for character in text if character not in encoded_texts)
    )
    return {
        "furthest_reachable_prefix_length": furthest,
        "reachable_prefix": text[:furthest],
        "remaining_suffix": text[furthest:],
        "earliest_reachable_suffix_offset": earliest_suffix,
        "reachable_suffix": text[earliest_suffix:],
        "missing_standalone_characters": [
            {
                "text": character,
                "codepoint": f"U+{ord(character):04X}",
            }
            for character in missing_characters
        ],
        "reason": (
            "missing_encoded_single_character_foundation"
            if missing_characters
            else "no_complete_shorter_gated_component_path"
        ),
    }


def _encoded_texts(connection: sqlite3.Connection) -> set[str]:
    return {
        str(row[0])
        for row in connection.execute(
            """
            SELECT DISTINCT text
            FROM canonical_readings
            WHERE LENGTH(text) > 1 OR pronunciation_scope = 'standalone'
            """
        )
    }


def _target_rows(
    connection: sqlite3.Connection,
    *,
    minimum_target_length: int,
) -> Iterable[sqlite3.Row]:
    return connection.execute(
        """
        SELECT text, text_length, bcc_frequency
        FROM candidate_universe
        WHERE has_gated_reading = 0
          AND text_length >= ?
        ORDER BY text_length DESC, bcc_frequency DESC, text
        """,
        (minimum_target_length,),
    )


def _export_evidence(connection: sqlite3.Connection, path: Path) -> None:
    fields = (
        "text",
        "text_length",
        "bcc_frequency",
        "reachability_status",
        "preferred_parts_json",
        "preferred_segments_json",
        "minimum_leaf_parts",
        "minimum_segmentation_count",
        "structural_ambiguous",
        "encoded_multichar_coverage",
        "encoded_multichar_component_count",
        "dynamic_residual_blocks_json",
        "dynamic_residual_character_count",
        "single_exception_count",
        "reading_combination_count",
        "reading_ambiguous",
        "primary_marked_input",
        "primary_numeric_input",
        "recursive_depth",
        "blocker_json",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(
            connection.execute(
                f"""
                SELECT {", ".join(fields)}
                FROM recursive_composition_evidence
                ORDER BY text_length DESC, bcc_frequency DESC, text
                """
            )
        )


def build_recursive_composition_model(
    *,
    source_database: Path,
    input_model_database: Path,
    output_dir: Path,
    config: RecursiveCompositionConfig = RecursiveCompositionConfig(),
) -> RecursiveCompositionResult:
    """Build evidence without creating whole-string readings or decisions."""

    config.validate()
    source_database = source_database.resolve()
    input_model_database = input_model_database.resolve()
    output_dir = output_dir.resolve()
    if not source_database.is_file():
        raise FileNotFoundError(source_database)
    if not input_model_database.is_file():
        raise FileNotFoundError(input_model_database)
    output_dir.mkdir(parents=True, exist_ok=True)

    source = sqlite3.connect(
        f"file:{source_database.as_posix()}?mode=ro",
        uri=True,
    )
    source.row_factory = sqlite3.Row
    source.execute("PRAGMA query_only = ON")
    source_columns = {
        str(row[1])
        for row in source.execute("PRAGMA table_info(canonical_readings)")
    }
    required_columns = {
        "id",
        "text",
        "marked_pinyin",
        "numeric_pinyin",
        "reading_rank",
        "is_primary",
        "bcc_frequency",
    }
    missing_columns = required_columns - source_columns
    if missing_columns:
        source.close()
        raise ValueError(
            "canonical_readings is missing columns: "
            + ", ".join(sorted(missing_columns))
        )
    if "pronunciation_scope" not in source_columns:
        source.close()
        raise ValueError(
            "canonical_readings must expose pronunciation_scope"
        )

    all_encoded_texts = _encoded_texts(source)
    encoded_multichar_texts = {
        text for text in all_encoded_texts if len(text) >= 2
    }

    @lru_cache(maxsize=500_000)
    def readings(text: str) -> tuple[dict[str, Any], ...]:
        scope_clause = (
            "AND pronunciation_scope = 'standalone'" if len(text) == 1 else ""
        )
        rows = source.execute(
            f"""
            SELECT id, marked_pinyin, numeric_pinyin, is_primary,
                   reading_rank, bcc_frequency
            FROM canonical_readings
            WHERE text = ?
            {scope_clause}
            ORDER BY is_primary DESC, reading_rank, id
            """,
            (text,),
        )
        return tuple(
            {
                "reading_id": int(row["id"]),
                "marked": str(row["marked_pinyin"]),
                "numeric": str(row["numeric_pinyin"]),
                "is_primary": bool(row["is_primary"]),
                "bcc_frequency": int(row["bcc_frequency"]),
            }
            for row in rows
        )

    generation = datetime.now(timezone.utc).isoformat()
    with InputModelStore(input_model_database) as store:
        connection = store.connection
        connection.row_factory = sqlite3.Row
        connection.execute("BEGIN IMMEDIATE")
        try:
            connection.execute("DELETE FROM recursive_composition_evidence")
            batch: list[tuple[object, ...]] = []
            target_count = 0
            reachable_count = 0
            structural_ambiguous_count = 0
            reading_ambiguous_count = 0
            for row in _target_rows(
                connection,
                minimum_target_length=config.minimum_target_length,
            ):
                target_count += 1
                text = str(row["text"])
                coverage_plan = _best_coverage_plans(
                    text,
                    encoded_multichar_texts,
                    maximum_alternatives=config.maximum_alternatives,
                )
                preferred_segments = _materialize_segments(
                    coverage_plan.alternatives[0],
                    all_encoded_texts,
                )
                alternative_segments = tuple(
                    _materialize_segments(plan, all_encoded_texts)
                    for plan in coverage_plan.alternatives
                )
                component_evidence: list[dict[str, Any]] = []
                reading_combination_count = 1
                missing_characters: list[str] = []
                for segment in preferred_segments:
                    segment_text = str(segment["text"])
                    if segment["kind"] == "encoded_multichar":
                        segment_readings = readings(segment_text)
                        if not segment_readings:
                            raise RuntimeError(
                                "encoded component has no usable reading: "
                                + segment_text
                            )
                        evidence = {
                            **segment,
                            "text_length": len(segment_text),
                            "reading_count": len(segment_readings),
                            "primary": segment_readings[0],
                            "readings": segment_readings[
                                : config.maximum_component_readings
                            ],
                            "readings_truncated": (
                                len(segment_readings)
                                > config.maximum_component_readings
                            ),
                        }
                    else:
                        missing_characters.extend(
                            str(character)
                            for character in segment["missing_characters"]
                        )
                        internal_parts = [
                            str(part) for part in segment["internal_parts"]
                        ]
                        if not internal_parts:
                            continue
                        reading_groups = [
                            readings(part) for part in internal_parts
                        ]
                        segment_reading_count = math.prod(
                            len(group) for group in reading_groups
                        )
                        primary_readings = [
                            group[0] for group in reading_groups
                        ]
                        evidence = {
                            **segment,
                            "text_length": len(segment_text),
                            "reading_count": segment_reading_count,
                            "primary": {
                                "reading_id": [
                                    item["reading_id"]
                                    for item in primary_readings
                                ],
                                "marked": " ".join(
                                    str(item["marked"])
                                    for item in primary_readings
                                ),
                                "numeric": " ".join(
                                    str(item["numeric"])
                                    for item in primary_readings
                                ),
                                "is_primary": all(
                                    bool(item["is_primary"])
                                    for item in primary_readings
                                ),
                            },
                            "readings": [],
                            "readings_truncated": (
                                segment_reading_count > 1
                            ),
                            "internal_reading_groups": reading_groups,
                        }
                    reading_combination_count *= int(
                        evidence["reading_count"]
                    )
                    component_evidence.append(evidence)

                encoded_multichar_parts = [
                    str(segment["text"])
                    for segment in preferred_segments
                    if segment["kind"] == "encoded_multichar"
                ]
                for segment in preferred_segments:
                    if segment["kind"] == "encoded_multichar":
                        continue
                    encoded_multichar_parts.extend(
                        str(part)
                        for part in segment["internal_parts"]
                        if len(str(part)) >= 2
                    )
                dynamic_residuals = [
                    segment
                    for segment in preferred_segments
                    if segment["kind"] != "encoded_multichar"
                ]
                encoded_multichar_coverage = sum(
                    len(part) for part in encoded_multichar_parts
                )
                dynamic_residual_character_count = sum(
                    len(str(segment["text"]))
                    for segment in dynamic_residuals
                )
                single_exception_count = len(
                    tuple(dict.fromkeys(missing_characters))
                )
                reachable = not missing_characters
                if not reachable:
                    values: tuple[object, ...] = (
                        text,
                        int(row["text_length"]),
                        int(row["bcc_frequency"]),
                        "unreachable",
                        json.dumps(
                            [item["text"] for item in preferred_segments],
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            preferred_segments,
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            [
                                [item["text"] for item in alternative]
                                for alternative in alternative_segments
                            ],
                            ensure_ascii=False,
                        ),
                        len(preferred_segments),
                        str(coverage_plan.count),
                        int(coverage_plan.truncated),
                        int(coverage_plan.count > 1),
                        "0",
                        0,
                        "",
                        "",
                        0,
                        max(
                            (len(str(item["text"])) for item in preferred_segments),
                            default=0,
                        ),
                        single_exception_count,
                        encoded_multichar_coverage,
                        len(encoded_multichar_parts),
                        json.dumps(
                            dynamic_residuals,
                            ensure_ascii=False,
                        ),
                        dynamic_residual_character_count,
                        single_exception_count,
                        json.dumps(
                            _blocker(text, all_encoded_texts),
                            ensure_ascii=False,
                        ),
                        EVIDENCE_RULE,
                        0,
                        generation,
                    )
                else:
                    reachable_count += 1
                    structural_ambiguous = coverage_plan.count > 1
                    reading_ambiguous = reading_combination_count > 1
                    structural_ambiguous_count += int(structural_ambiguous)
                    reading_ambiguous_count += int(reading_ambiguous)
                    _tree, recursive_depth = build_composition_tree(
                        component_evidence,
                        maximum_parts_per_step=(
                            config.maximum_parts_per_step
                        ),
                    )
                    values = (
                        text,
                        int(row["text_length"]),
                        int(row["bcc_frequency"]),
                        "reachable",
                        json.dumps(
                            [item["text"] for item in preferred_segments],
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            preferred_segments,
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            [
                                [item["text"] for item in alternative]
                                for alternative in alternative_segments
                            ],
                            ensure_ascii=False,
                        ),
                        len(preferred_segments),
                        str(coverage_plan.count),
                        int(coverage_plan.truncated),
                        int(structural_ambiguous),
                        str(reading_combination_count),
                        int(reading_ambiguous),
                        " ".join(
                            str(item["primary"]["marked"])
                            for item in component_evidence
                        ),
                        " ".join(
                            str(item["primary"]["numeric"])
                            for item in component_evidence
                        ),
                        recursive_depth,
                        max(
                            len(str(item["text"]))
                            for item in preferred_segments
                        ),
                        single_exception_count,
                        encoded_multichar_coverage,
                        len(encoded_multichar_parts),
                        json.dumps(
                            dynamic_residuals,
                            ensure_ascii=False,
                        ),
                        dynamic_residual_character_count,
                        single_exception_count,
                        "{}",
                        EVIDENCE_RULE,
                        0,
                        generation,
                    )
                batch.append(values)
                if len(batch) >= 20_000:
                    connection.executemany(
                        """
                        INSERT INTO recursive_composition_evidence
                        VALUES (
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                        )
                        """,
                        batch,
                    )
                    batch.clear()
            if batch:
                connection.executemany(
                    """
                    INSERT INTO recursive_composition_evidence
                    VALUES (
                        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                    )
                    """,
                    batch,
                )

            metadata = {
                "recursive_composition_model_version": MODEL_VERSION,
                "recursive_composition_generation": generation,
                "recursive_composition_target_count": str(target_count),
                "recursive_composition_reachable_count": str(
                    reachable_count
                ),
                "recursive_composition_unreachable_count": str(
                    target_count - reachable_count
                ),
                "recursive_composition_structural_ambiguous_count": str(
                    structural_ambiguous_count
                ),
                "recursive_composition_reading_ambiguous_count": str(
                    reading_ambiguous_count
                ),
                "recursive_composition_maximum_parts_per_step": str(
                    config.maximum_parts_per_step
                ),
            }
            connection.executemany(
                """
                INSERT INTO metadata(key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                metadata.items(),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
    source.close()

    with sqlite3.connect(input_model_database) as report:
        report.row_factory = sqlite3.Row
        evidence_tsv = output_dir / "recursive_composition_evidence.tsv"
        _export_evidence(report, evidence_tsv)
        length_rows = [
            {
                "text_length": int(row["text_length"]),
                "target_count": int(row["target_count"]),
                "reachable_count": int(row["reachable_count"]),
            }
            for row in report.execute(
                """
                SELECT text_length, COUNT(*) AS target_count,
                       SUM(reachability_status = 'reachable')
                           AS reachable_count
                FROM recursive_composition_evidence
                GROUP BY text_length
                ORDER BY text_length DESC
                """
            )
        ]
        uses_multichar_component_count = int(
            report.execute(
                """
                SELECT COUNT(*)
                FROM recursive_composition_evidence
                WHERE reachability_status = 'reachable'
                  AND encoded_multichar_component_count > 0
                """
            ).fetchone()[0]
        )
        single_exception_target_count = int(
            report.execute(
                """
                SELECT COUNT(*)
                FROM recursive_composition_evidence
                WHERE single_exception_count > 0
                """
            ).fetchone()[0]
        )

    unreachable_count = target_count - reachable_count
    residual_blocks_only_count = (
        reachable_count - uses_multichar_component_count
    )
    manifest_payload = {
        "schema_version": MODEL_VERSION,
        "source_database": str(source_database),
        "input_model_database": str(input_model_database),
        "configuration": {
            "minimum_target_length": config.minimum_target_length,
            "maximum_alternatives": config.maximum_alternatives,
            "maximum_parts_per_step": config.maximum_parts_per_step,
            "maximum_component_readings": (
                config.maximum_component_readings
            ),
        },
        "semantics": {
            "components_require_source_gated_readings": True,
            "components_require_manual_label": False,
            "target_whole_reading_is_not_created": True,
            "changes_candidate_disposition": False,
            "top_level_single_components_allowed": False,
            "known_encoded_multichar_coverage_is_preferred": True,
            "default_residual_block_size": 2,
            "larger_residual_blocks_prevent_single_exposure": [3, 4],
            "single_readings_used_only_inside_residual_blocks": True,
            "missing_single_foundation_is_exception": True,
        },
        "counts": {
            "targets": target_count,
            "reachable": reachable_count,
            "unreachable": unreachable_count,
            "structurally_ambiguous": structural_ambiguous_count,
            "reading_ambiguous": reading_ambiguous_count,
            "uses_multichar_component": uses_multichar_component_count,
            "residual_blocks_only": residual_blocks_only_count,
            "single_exception_targets": single_exception_target_count,
        },
        "length_groups": length_rows,
        "outputs": {
            "evidence_tsv": evidence_tsv.name,
            "summary": "summary.md",
        },
    }
    manifest = output_dir / "manifest.json"
    manifest.write_text(
        json.dumps(manifest_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    summary_markdown = output_dir / "summary.md"
    coverage = reachable_count / target_count if target_count else 0.0
    summary_markdown.write_text(
        "\n".join(
            (
                "# 未编码长串递归动态组合模型",
                "",
                f"- 未编码目标：`{target_count:,}`",
                f"- 可由较短已编码串递归组成：`{reachable_count:,}`",
                f"- 尚无完整组合路径：`{unreachable_count:,}`",
                f"- 可达率：`{coverage:.4%}`",
                f"- 结构多解：`{structural_ambiguous_count:,}`",
                f"- 组件读音多解：`{reading_ambiguous_count:,}`",
                f"- 使用至少一个多字已编码组件：`{uses_multichar_component_count:,}`",
                f"- 仅由2–4字动态残余块到达：`{residual_blocks_only_count:,}`",
                f"- 含缺失单字根基例外：`{single_exception_target_count:,}`",
                "",
                "组合拼音只是已编码组件的输入序列，不是目标长串的来源词音；"
                "本模型不改变候选去留。",
                "",
            )
        ),
        encoding="utf-8",
    )
    return RecursiveCompositionResult(
        input_model_database=input_model_database,
        output_dir=output_dir,
        evidence_tsv=evidence_tsv,
        summary_markdown=summary_markdown,
        manifest=manifest,
        target_count=target_count,
        reachable_count=reachable_count,
        unreachable_count=unreachable_count,
        structurally_ambiguous_count=structural_ambiguous_count,
        reading_ambiguous_count=reading_ambiguous_count,
        uses_multichar_component_count=uses_multichar_component_count,
        residual_blocks_only_count=residual_blocks_only_count,
        single_exception_target_count=single_exception_target_count,
    )
