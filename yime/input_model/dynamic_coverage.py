"""R0-R5 dynamic reconstruction coverage over the encoded candidate pool."""

from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote


DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[2]
    / "internal_data"
    / "dynamic_candidate_coverage_policy.json"
)


@dataclass(frozen=True)
class DynamicCoverageResult:
    encoded_texts: int
    classified_texts: int
    outside_encoded_capacity_texts: int
    level_counts: dict[str, int]
    level_frequency: dict[str, int]
    selected_texts: int
    classified_selected_texts: int
    selected_counts: dict[str, dict[str, int]]
    residual_samples: dict[str, tuple[dict[str, object], ...]]
    completion_passed: bool


def _readonly_uri(path: Path) -> str:
    return f"file:{quote(path.resolve().as_posix(), safe='/:')}?mode=ro"


def _load_policy(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported dynamic coverage policy schema")
    safeguards = payload.get("safeguards", {})
    required = (
        "source_inventory_is_read_only",
        "frequency_is_not_invalidity",
        "dynamic_reachability_is_not_lexical_rejection",
        "component_or_rule_is_preferred_over_whole_string_promotion",
        "every_encoded_text_receives_one_level",
    )
    if any(safeguards.get(key) is not True for key in required):
        raise ValueError("dynamic coverage policy is missing a safeguard")
    return payload


def evaluate_dynamic_candidate_coverage(
    *,
    capacity_database: Path,
    input_model_database: Path,
    selection_path: Path,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> DynamicCoverageResult:
    """Assign every encoded text one coverage level without mutating inputs."""

    policy = _load_policy(policy_path)
    thresholds = policy["thresholds"]
    maximum_parts = int(thresholds["maximum_reliable_component_count"])
    maximum_alternatives = int(
        thresholds["maximum_reliable_minimum_decompositions"]
    )
    sample_limit = int(thresholds["residual_sample_limit"])
    protected = tuple(policy["protected_candidate_classes"])
    invalid = tuple(policy["invalid_candidate_classes"])
    protected_placeholders = ", ".join("?" for _ in protected)
    invalid_placeholders = ", ".join("?" for _ in invalid)

    connection = sqlite3.connect(_readonly_uri(capacity_database), uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            "ATTACH DATABASE ? AS input_model",
            (_readonly_uri(input_model_database),),
        )
        connection.execute(
            f"""
            CREATE TEMP TABLE coverage_assignments AS
            WITH reading_stats AS (
                SELECT text,
                       MAX(direct_part_count) AS maximum_parts,
                       MAX(alternative_count) AS maximum_alternatives
                FROM reading_analysis
                GROUP BY text
            )
            SELECT
                i.text,
                i.text_length,
                i.bcc_frequency,
                i.reading_count,
                i.recoverable_reading_count,
                i.mandatory_static,
                i.mandatory_reasons,
                i.dependent_reading_count,
                i.dependent_frequency,
                i.utility_score,
                i.recommended_disposition,
                COALESCE(u.baseline_class, 'unknown') AS candidate_class,
                COALESCE(u.baseline_policy, 'needs_review') AS baseline_policy,
                COALESCE(a.candidate_class, '') AS assessed_class,
                COALESCE(a.integration_policy, '') AS assessed_policy,
                COALESCE(a.decision_status, '') AS decision_status,
                COALESCE(r.maximum_parts, 0) AS maximum_parts,
                COALESCE(r.maximum_alternatives, 0) AS maximum_alternatives,
                CASE
                    WHEN COALESCE(a.candidate_class, '') IN ({invalid_placeholders})
                      OR COALESCE(a.decision_status, '') = 'rejected'
                      OR INSTR(i.mandatory_reasons, 'syllable_alignment_mismatch') > 0
                        THEN 'R0'
                    WHEN INSTR(i.mandatory_reasons, 'single_character_foundation') > 0
                        THEN 'R5'
                    WHEN i.recoverable_reading_count = 0
                        THEN 'R1'
                    WHEN i.recoverable_reading_count < i.reading_count
                        THEN 'R2'
                    WHEN COALESCE(a.integration_policy, '') = 'static_keep'
                      OR i.recommended_disposition IN (
                            'mandatory_static', 'selected_static'
                         )
                      OR COALESCE(u.baseline_class, 'unknown')
                            IN ({protected_placeholders})
                      OR COALESCE(u.baseline_policy, '') = 'static_keep'
                        THEN 'R5'
                    WHEN COALESCE(r.maximum_parts, 0) > ?
                      OR COALESCE(r.maximum_alternatives, 0) > ?
                        THEN 'R3'
                    ELSE 'R4'
                END AS coverage_level
            FROM static_capacity_items AS i
            LEFT JOIN reading_stats AS r USING (text)
            LEFT JOIN input_model.candidate_universe AS u USING (text)
            LEFT JOIN input_model.assessments AS a USING (text)
            """,
            (*invalid, *protected, maximum_parts, maximum_alternatives),
        )
        encoded_texts = int(
            connection.execute(
                "SELECT COUNT(*) FROM static_capacity_items"
            ).fetchone()[0]
        )
        classified_texts = int(
            connection.execute(
                "SELECT COUNT(*) FROM coverage_assignments"
            ).fetchone()[0]
        )
        outside_encoded = int(
            connection.execute(
                """
                SELECT COUNT(*)
                FROM input_model.candidate_universe AS u
                LEFT JOIN static_capacity_items AS i USING (text)
                WHERE i.text IS NULL
                """
            ).fetchone()[0]
        )
        level_counts = {
            str(row["coverage_level"]): int(row["item_count"])
            for row in connection.execute(
                """
                SELECT coverage_level, COUNT(*) AS item_count
                FROM coverage_assignments
                GROUP BY coverage_level
                ORDER BY coverage_level
                """
            )
        }
        level_frequency = {
            str(row["coverage_level"]): int(row["total_frequency"])
            for row in connection.execute(
                """
                SELECT coverage_level,
                       COALESCE(SUM(bcc_frequency), 0) AS total_frequency
                FROM coverage_assignments
                GROUP BY coverage_level
                ORDER BY coverage_level
                """
            )
        }
        residual_samples: dict[
            str,
            tuple[dict[str, object], ...],
        ] = {}
        for level in ("R0", "R1", "R2", "R3"):
            rows = connection.execute(
                """
                SELECT text, text_length, bcc_frequency, reading_count,
                       recoverable_reading_count, maximum_parts,
                       maximum_alternatives, dependent_reading_count,
                       candidate_class, mandatory_reasons
                FROM coverage_assignments
                WHERE coverage_level = ?
                ORDER BY dependent_reading_count DESC,
                         bcc_frequency DESC, utility_score DESC, text
                LIMIT ?
                """,
                (level, sample_limit),
            ).fetchall()
            residual_samples[level] = tuple(
                {key: row[key] for key in row.keys()} for row in rows
            )

        connection.execute(
            """
            CREATE TEMP TABLE selected_runtime (
                text TEXT NOT NULL,
                selection_level TEXT NOT NULL,
                PRIMARY KEY(text, selection_level)
            )
            """
        )
        with selection_path.open(encoding="utf-8", newline="") as stream:
            selected = {
                (
                    str(row.get("text", "")),
                    str(row.get("selection_level", "")),
                )
                for row in csv.DictReader(stream, delimiter="\t")
                if str(row.get("text", ""))
                and str(row.get("selection_level", ""))
            }
        connection.executemany(
            "INSERT INTO selected_runtime VALUES (?, ?)",
            sorted(selected),
        )
        selected_texts = int(
            connection.execute(
                "SELECT COUNT(*) FROM selected_runtime"
            ).fetchone()[0]
        )
        classified_selected_texts = int(
            connection.execute(
                """
                SELECT COUNT(*)
                FROM selected_runtime AS s
                JOIN coverage_assignments AS a USING (text)
                """
            ).fetchone()[0]
        )
        selected_counts: dict[str, dict[str, int]] = {}
        for row in connection.execute(
            """
            SELECT s.selection_level, a.coverage_level,
                   COUNT(*) AS item_count
            FROM selected_runtime AS s
            JOIN coverage_assignments AS a USING (text)
            GROUP BY s.selection_level, a.coverage_level
            ORDER BY s.selection_level, a.coverage_level
            """
        ):
            selected_counts.setdefault(
                str(row["selection_level"]),
                {},
            )[str(row["coverage_level"])] = int(row["item_count"])
    finally:
        connection.close()

    gate = policy["completion_gate"]
    completion_passed = (
        classified_texts == encoded_texts
        and level_counts.get("R0", 0) <= int(gate["maximum_r0_items"])
        and selected_texts > 0
        and classified_selected_texts == selected_texts
        and all(level in residual_samples for level in ("R0", "R1", "R2", "R3"))
    )
    return DynamicCoverageResult(
        encoded_texts=encoded_texts,
        classified_texts=classified_texts,
        outside_encoded_capacity_texts=outside_encoded,
        level_counts=level_counts,
        level_frequency=level_frequency,
        selected_texts=selected_texts,
        classified_selected_texts=classified_selected_texts,
        selected_counts=selected_counts,
        residual_samples=residual_samples,
        completion_passed=completion_passed,
    )
