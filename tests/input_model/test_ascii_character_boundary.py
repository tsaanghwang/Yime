"""Disabled readings change effective coverage, never canonical admission."""

import sqlite3

import pytest

from tools.build_two_level_runtime_trial import (
    _assert_character_boundary,
    active_character_boundary,
)


def source_database(tmp_path):
    path = tmp_path / "source.sqlite3"
    with sqlite3.connect(path) as connection:
        connection.executescript("""
            CREATE TABLE character_tiers (
                hanzi TEXT, tier_number INTEGER, encoded_reading_count INTEGER
            );
            CREATE TABLE canonical_readings (
                text TEXT, numeric_pinyin TEXT, pronunciation_scope TEXT
            );
            INSERT INTO character_tiers VALUES ('甲', 1, 2), ('乙', 1, 1), ('丙', 1, 1);
            INSERT INTO canonical_readings VALUES
                ('甲', 'ba1', 'standalone'), ('甲', 'm1', 'standalone'),
                ('乙', 'm1', 'standalone'), ('丙', 'ba1', 'phrase_only');
        """)
    return path


def test_disabled_reading_boundary_preserves_original_source_gate(tmp_path):
    policy = {
        "maximum_tier": 8,
        "expected_distinct_characters": 2,
        "expected_source_reading_entries": 3,
        "expected_runtime_mapping_entries": 3,
    }
    boundary = active_character_boundary(source_database(tmp_path), policy)
    assert boundary == {
        "source_distinct_characters": 2,
        "source_reading_entries": 3,
        "active_distinct_characters": 1,
        "active_source_reading_entries": 1,
        "active_runtime_mapping_entries": 1,
        "excluded_disabled_readings": 2,
        "excluded_disabled_only_characters": 1,
    }
    manifest = {
        "distinct_texts_by_length": {"1": 1},
        "reading_entries_by_length": {"1": 1},
        "allowed_encoded_hanzi": 2,
    }
    assert _assert_character_boundary(
        manifest, policy, label="test", active_boundary=boundary,
        expected_readings_field="expected_source_reading_entries",
    ) == {"distinct_characters": 1, "reading_entries": 1}
    with pytest.raises(ValueError, match="single-character coverage mismatch"):
        _assert_character_boundary(
            manifest, policy, label="legacy gate",
            expected_readings_field="expected_source_reading_entries",
        )
    manifest["allowed_encoded_hanzi"] = 1
    with pytest.raises(ValueError, match="allowed-character inventory mismatch"):
        _assert_character_boundary(
            manifest, policy, label="test", active_boundary=boundary,
            expected_readings_field="expected_source_reading_entries",
        )


def test_changed_source_counts_are_not_excused_by_disabled_readings(tmp_path):
    with pytest.raises(ValueError, match="Canonical character source changed"):
        active_character_boundary(source_database(tmp_path), {
            "maximum_tier": 8,
            "expected_distinct_characters": 1,
            "expected_source_reading_entries": 1,
        })
