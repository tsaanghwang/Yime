from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path

from yime.input_model.long_form_migration import (
    audit_long_form_core_migration,
)


def _policy(path: Path) -> Path:
    path.write_text(
        json.dumps(
            {
                "long_form_core_migration": {
                    "minimum_text_length": 5,
                    "eligible_candidate_classes": [
                        "lexical_candidate",
                        "productive_phrase",
                    ],
                    "protected_candidate_classes": [
                        "domain_term",
                        "place_name",
                        "person_name",
                    ],
                    "action": (
                        "exclude_from_static_core_keep_dynamic_recoverable"
                    ),
                    "source_mutation": False,
                    "noise_label": False,
                }
            }
        ),
        encoding="utf-8",
    )
    return path


def _databases(capacity: Path, input_model: Path) -> None:
    with sqlite3.connect(capacity) as connection:
        connection.executescript(
            """
            CREATE TABLE static_capacity_items (
                text TEXT PRIMARY KEY,
                text_length INTEGER,
                bcc_frequency INTEGER,
                reading_count INTEGER,
                recoverable_reading_count INTEGER,
                mandatory_static INTEGER,
                dependent_reading_count INTEGER,
                recommended_disposition TEXT
            );
            INSERT INTO static_capacity_items VALUES
                ('整句可以动态恢复', 8, 0, 1, 1, 0, 0,
                 'dynamic_migration_candidate'),
                ('专业领域固定名称', 8, 0, 1, 1, 0, 0,
                 'dynamic_migration_candidate'),
                ('具有直接证据长词', 8, 10, 1, 1, 0, 0,
                 'selected_static'),
                ('四字词语', 4, 0, 1, 1, 0, 0,
                 'dynamic_migration_candidate');
            """
        )
    with sqlite3.connect(input_model) as connection:
        connection.executescript(
            """
            CREATE TABLE candidate_universe (
                text TEXT PRIMARY KEY,
                baseline_class TEXT
            );
            INSERT INTO candidate_universe VALUES
                ('整句可以动态恢复', 'productive_phrase'),
                ('专业领域固定名称', 'domain_term'),
                ('具有直接证据长词', 'lexical_candidate'),
                ('四字词语', 'lexical_candidate');
            """
        )


def _selection(path: Path, texts: tuple[str, ...]) -> Path:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=(
                "text",
                "selection_level",
                "selection_reason",
            ),
            delimiter="\t",
        )
        writer.writeheader()
        for text in texts:
            writer.writerow(
                {
                    "text": text,
                    "selection_level": "second_level",
                    "selection_reason": "test",
                }
            )
    return path


def test_audit_separates_migration_candidates_from_protected_classes(
    tmp_path: Path,
) -> None:
    capacity = tmp_path / "capacity.sqlite3"
    input_model = tmp_path / "input.sqlite3"
    _databases(capacity, input_model)
    audit = audit_long_form_core_migration(
        capacity_database=capacity,
        input_model_database=input_model,
        policy_path=_policy(tmp_path / "policy.json"),
    )
    assert audit.eligible_texts == 1
    assert audit.protected_texts == 1
    assert audit.counts_by_class == {"productive_phrase": 1}


def test_audit_fails_only_when_eligible_long_form_leaks_into_selection(
    tmp_path: Path,
) -> None:
    capacity = tmp_path / "capacity.sqlite3"
    input_model = tmp_path / "input.sqlite3"
    _databases(capacity, input_model)
    selection = _selection(
        tmp_path / "selection.tsv",
        (
            "整句可以动态恢复",
            "专业领域固定名称",
            "具有直接证据长词",
        ),
    )
    audit = audit_long_form_core_migration(
        capacity_database=capacity,
        input_model_database=input_model,
        selection_path=selection,
        policy_path=_policy(tmp_path / "policy.json"),
    )
    assert audit.selected_long_texts == 3
    assert audit.selected_violations == 1
    assert audit.violation_samples[0]["text"] == "整句可以动态恢复"
