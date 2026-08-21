from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path

from yime.input_model.dynamic_coverage import (
    evaluate_dynamic_candidate_coverage,
)


def _policy(path: Path) -> Path:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "thresholds": {
                    "maximum_reliable_component_count": 2,
                    "maximum_reliable_minimum_decompositions": 2,
                    "residual_sample_limit": 10,
                },
                "protected_candidate_classes": ["domain_term"],
                "invalid_candidate_classes": ["noise"],
                "safeguards": {
                    "source_inventory_is_read_only": True,
                    "frequency_is_not_invalidity": True,
                    "dynamic_reachability_is_not_lexical_rejection": True,
                    "component_or_rule_is_preferred_over_whole_string_promotion": True,
                    "every_encoded_text_receives_one_level": True,
                },
                "completion_gate": {
                    "maximum_r0_items": 0,
                },
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
                text TEXT PRIMARY KEY, text_length INTEGER,
                bcc_frequency INTEGER, reading_count INTEGER,
                recoverable_reading_count INTEGER,
                mandatory_static INTEGER, mandatory_reasons TEXT,
                dependent_reading_count INTEGER,
                dependent_frequency INTEGER, utility_score REAL,
                recommended_disposition TEXT
            );
            CREATE TABLE reading_analysis (
                text TEXT, direct_part_count INTEGER,
                alternative_count INTEGER
            );
            INSERT INTO static_capacity_items VALUES
                ('基', 1, 1, 1, 0, 1, 'single_character_foundation',
                 5, 5, 5, 'mandatory_static'),
                ('不可达', 3, 0, 1, 0, 1,
                 'no_shorter_attested_reading_decomposition',
                 0, 0, 0, 'mandatory_static'),
                ('部分可达', 4, 1, 2, 1, 1,
                 'no_shorter_attested_reading_decomposition',
                 0, 0, 1, 'mandatory_static'),
                ('搜索较深', 4, 0, 1, 1, 0, '',
                 0, 0, 1, 'dynamic_migration_candidate'),
                ('动态可达', 4, 0, 1, 1, 0, '',
                 0, 0, 1, 'dynamic_migration_candidate'),
                ('领域固定', 4, 0, 1, 1, 0, '',
                 0, 0, 1, 'dynamic_migration_candidate');
            INSERT INTO reading_analysis VALUES
                ('基', 0, 0), ('不可达', 0, 0), ('部分可达', 2, 1),
                ('搜索较深', 3, 1), ('动态可达', 2, 1),
                ('领域固定', 2, 1);
            """
        )
    with sqlite3.connect(input_model) as connection:
        connection.executescript(
            """
            CREATE TABLE candidate_universe (
                text TEXT PRIMARY KEY, baseline_class TEXT,
                baseline_policy TEXT
            );
            CREATE TABLE assessments (
                text TEXT PRIMARY KEY, candidate_class TEXT,
                integration_policy TEXT, decision_status TEXT
            );
            INSERT INTO candidate_universe VALUES
                ('基', 'single_character', 'static_keep'),
                ('不可达', 'lexical_candidate', 'needs_review'),
                ('部分可达', 'lexical_candidate', 'needs_review'),
                ('搜索较深', 'lexical_candidate', 'needs_review'),
                ('动态可达', 'lexical_candidate', 'needs_review'),
                ('领域固定', 'domain_term', 'static_keep'),
                ('未编码项', 'unknown', 'needs_review');
            """
        )


def _selection(path: Path) -> Path:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=("text", "selection_level"),
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerow({"text": "基", "selection_level": "first_level"})
        writer.writerow(
            {"text": "动态可达", "selection_level": "second_level"}
        )
    return path


def test_every_encoded_text_receives_an_actionable_coverage_level(
    tmp_path: Path,
) -> None:
    capacity = tmp_path / "capacity.sqlite3"
    input_model = tmp_path / "input.sqlite3"
    _databases(capacity, input_model)
    result = evaluate_dynamic_candidate_coverage(
        capacity_database=capacity,
        input_model_database=input_model,
        selection_path=_selection(tmp_path / "selection.tsv"),
        policy_path=_policy(tmp_path / "policy.json"),
    )
    assert result.encoded_texts == result.classified_texts == 6
    assert result.outside_encoded_capacity_texts == 1
    assert result.selected_texts == result.classified_selected_texts == 2
    assert result.level_counts == {
        "R1": 1,
        "R2": 1,
        "R3": 1,
        "R4": 1,
        "R5": 2,
    }
    assert result.selected_counts == {
        "first_level": {"R5": 1},
        "second_level": {"R4": 1},
    }
    assert result.completion_passed


def test_unclassified_runtime_selection_fails_completion_gate(
    tmp_path: Path,
) -> None:
    capacity = tmp_path / "capacity.sqlite3"
    input_model = tmp_path / "input.sqlite3"
    _databases(capacity, input_model)
    selection = _selection(tmp_path / "selection.tsv")
    with selection.open("a", encoding="utf-8", newline="") as stream:
        stream.write("未编码项\tsecond_level\n")
    result = evaluate_dynamic_candidate_coverage(
        capacity_database=capacity,
        input_model_database=input_model,
        selection_path=selection,
        policy_path=_policy(tmp_path / "policy.json"),
    )
    assert result.selected_texts == 3
    assert result.classified_selected_texts == 2
    assert not result.completion_passed
