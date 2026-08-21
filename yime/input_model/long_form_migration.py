"""Audit rule-level migration of low-evidence long forms from static core."""

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
    / "runtime_lexicon_filter_policy.json"
)


@dataclass(frozen=True)
class LongFormMigrationAudit:
    eligible_texts: int
    protected_texts: int
    selected_long_texts: int
    selected_violations: int
    counts_by_class: dict[str, int]
    counts_by_length: dict[int, int]
    violation_samples: tuple[dict[str, object], ...]


def _readonly_uri(path: Path) -> str:
    return f"file:{quote(path.resolve().as_posix(), safe='/:')}?mode=ro"


def _load_policy(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    config = payload.get("long_form_core_migration", {})
    if config.get("source_mutation") is not False:
        raise ValueError("long-form migration must preserve source data")
    if config.get("noise_label") is not False:
        raise ValueError("long-form migration must not label entries as noise")
    if (
        config.get("action")
        != "exclude_from_static_core_keep_dynamic_recoverable"
    ):
        raise ValueError("unsupported long-form migration action")
    return config


def audit_long_form_core_migration(
    *,
    capacity_database: Path,
    input_model_database: Path,
    selection_path: Path | None = None,
    policy_path: Path = DEFAULT_POLICY_PATH,
    sample_limit: int = 100,
) -> LongFormMigrationAudit:
    """Audit migration eligibility and optional materialized-runtime leakage."""

    if sample_limit < 1:
        raise ValueError("sample_limit must be positive")
    policy = _load_policy(policy_path)
    minimum_length = int(policy["minimum_text_length"])
    eligible_classes = tuple(policy["eligible_candidate_classes"])
    protected_classes = tuple(policy["protected_candidate_classes"])
    connection = sqlite3.connect(_readonly_uri(capacity_database), uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            "ATTACH DATABASE ? AS input_model",
            (_readonly_uri(input_model_database),),
        )
        placeholders = ", ".join("?" for _ in eligible_classes)
        protected_placeholders = ", ".join("?" for _ in protected_classes)
        evidence_predicate = """
            i.text_length >= ?
            AND i.bcc_frequency = 0
            AND i.dependent_reading_count = 0
            AND i.mandatory_static = 0
            AND i.recoverable_reading_count = i.reading_count
        """
        eligible_parameters: tuple[object, ...] = (
            minimum_length,
            *eligible_classes,
        )
        eligible_predicate = (
            evidence_predicate
            + f" AND u.baseline_class IN ({placeholders})"
        )
        counts_by_class = {
            str(row["baseline_class"]): int(row["item_count"])
            for row in connection.execute(
                f"""
                SELECT u.baseline_class, COUNT(*) AS item_count
                FROM static_capacity_items AS i
                JOIN input_model.candidate_universe AS u USING (text)
                WHERE {eligible_predicate}
                GROUP BY u.baseline_class
                """,
                eligible_parameters,
            )
        }
        counts_by_length = {
            int(row["text_length"]): int(row["item_count"])
            for row in connection.execute(
                f"""
                SELECT i.text_length, COUNT(*) AS item_count
                FROM static_capacity_items AS i
                JOIN input_model.candidate_universe AS u USING (text)
                WHERE {eligible_predicate}
                GROUP BY i.text_length
                ORDER BY i.text_length
                """,
                eligible_parameters,
            )
        }
        protected_texts = int(
            connection.execute(
                f"""
                SELECT COUNT(*)
                FROM static_capacity_items AS i
                JOIN input_model.candidate_universe AS u USING (text)
                WHERE {evidence_predicate}
                  AND u.baseline_class IN ({protected_placeholders})
                """,
                (minimum_length, *protected_classes),
            ).fetchone()[0]
        )

        selected_long_texts = 0
        selected_violations = 0
        violation_samples: tuple[dict[str, object], ...] = ()
        if selection_path is not None:
            connection.execute(
                """
                CREATE TEMP TABLE selected_long (
                    text TEXT PRIMARY KEY
                )
                """
            )
            with selection_path.open(encoding="utf-8", newline="") as stream:
                selected = {
                    str(row["text"])
                    for row in csv.DictReader(stream, delimiter="\t")
                    if str(row.get("selection_level", "")) == "second_level"
                }
            connection.executemany(
                "INSERT INTO selected_long(text) VALUES (?)",
                ((text,) for text in selected),
            )
            selected_long_texts = len(selected)
            violation_rows = connection.execute(
                f"""
                SELECT i.text, i.text_length, u.baseline_class,
                       i.recommended_disposition
                FROM selected_long AS s
                JOIN static_capacity_items AS i USING (text)
                JOIN input_model.candidate_universe AS u USING (text)
                WHERE {eligible_predicate}
                ORDER BY i.text_length DESC, i.text
                """,
                eligible_parameters,
            ).fetchall()
            selected_violations = len(violation_rows)
            violation_samples = tuple(
                {
                    "text": str(row["text"]),
                    "text_length": int(row["text_length"]),
                    "candidate_class": str(row["baseline_class"]),
                    "recommended_disposition": str(
                        row["recommended_disposition"]
                    ),
                }
                for row in violation_rows[:sample_limit]
            )
    finally:
        connection.close()

    return LongFormMigrationAudit(
        eligible_texts=sum(counts_by_class.values()),
        protected_texts=protected_texts,
        selected_long_texts=selected_long_texts,
        selected_violations=selected_violations,
        counts_by_class=counts_by_class,
        counts_by_length=counts_by_length,
        violation_samples=violation_samples,
    )
