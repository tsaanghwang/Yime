from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from tools.build_two_level_runtime_trial import _assert_character_boundary
from tools.build_two_level_precomposition_lexicon import (
    build as build_two_level_dictionary,
)
from tools.prepare_component_learning_trial import build_dictionary


ROOT = Path(__file__).resolve().parents[2]


def _source_dictionary(path: Path) -> Path:
    path.write_text(
        "---\n"
        "name: test\n"
        "sort: by_weight\n"
        "...\n"
        "常\taaaa\t3000\n"
        "僻\tbbbb\t20\n"
        "无\tcccc\t1\n"
        "常僻\taaaabbbb\t10\n",
        encoding="utf-8",
    )
    return path


def _character_database(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE character_tiers (
                hanzi TEXT PRIMARY KEY,
                tier_number INTEGER NOT NULL,
                encoded_reading_count INTEGER NOT NULL
            );
            INSERT INTO character_tiers VALUES
                ('常', 1, 1),
                ('僻', 8, 1),
                ('无', 9, 0);
            CREATE TABLE canonical_readings (
                text TEXT NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                wanxiang_weight INTEGER NOT NULL
            );
            INSERT INTO canonical_readings VALUES
                ('常', 3000, 0),
                ('僻', 20, 0),
                ('常僻', 10, 0);
            """
        )
    return path


def test_policy_keeps_all_formally_encoded_characters_as_runtime_foundation() -> None:
    policy = json.loads(
        (
            ROOT / "internal_data" / "runtime_lexicon_filter_policy.json"
        ).read_text(encoding="utf-8")
    )
    boundary = policy["character_boundary"]
    assert boundary == {
        "maximum_tier": 8,
        "expected_distinct_characters": 46095,
        "expected_source_reading_entries": 61011,
        "expected_runtime_mapping_entries": 61010,
        "core_maximum_tier": 5,
        "core_distinct_characters": 14000,
        "peripheral_minimum_tier": 6,
        "peripheral_maximum_tier": 8,
        "peripheral_distinct_characters": 32095,
    }
    assert policy["single_character_ranking"] == {
        "core_weight_offset": 100000000,
        "peripheral_weight_offset": 0,
        "require_core_above_peripheral": True,
    }


def test_component_dictionary_includes_tier8_and_excludes_unencoded_tier9(
    tmp_path: Path,
) -> None:
    manifest = build_dictionary(
        source=_source_dictionary(tmp_path / "source.dict.yaml"),
        output=tmp_path / "output.dict.yaml",
        database=_character_database(tmp_path / "source.sqlite3"),
        maximum_tier=8,
        maximum_length=4,
    )
    output = (tmp_path / "output.dict.yaml").read_text(encoding="utf-8")
    assert "常\taaaa\t3000" in output
    assert "僻\tbbbb\t20" in output
    assert "常僻\taaaabbbb\t10" in output
    assert "无\tcccc\t1" not in output
    assert manifest["allowed_encoded_hanzi"] == 2
    assert manifest["distinct_texts_by_length"]["1"] == 2
    assert manifest["reading_entries_by_length"]["1"] == 2


def test_core_and_peripheral_single_characters_use_disjoint_weight_ranges(
    tmp_path: Path,
) -> None:
    source = _source_dictionary(tmp_path / "source.dict.yaml")
    production = tmp_path / "production.dict.yaml"
    production.write_text(
        "---\n"
        "name: production\n"
        "sort: by_weight\n"
        "...\n"
        "常\taaaa\t3000\n"
        "常僻\taaaabbbb\t10\n",
        encoding="utf-8",
    )
    database = _character_database(tmp_path / "source.sqlite3")
    manifest = build_two_level_dictionary(
        base=source,
        production=production,
        output=tmp_path / "output.dict.yaml",
        manifest_path=tmp_path / "manifest.json",
        database=database,
        capacity=0,
        maximum_tier=8,
        minimum_length=5,
        retained_long_dictionary=None,
        core_maximum_tier=5,
        core_weight_offset=100000000,
        peripheral_weight_offset=0,
        require_core_above_peripheral=True,
    )
    weights = {}
    for line in (tmp_path / "output.dict.yaml").read_text(
        encoding="utf-8"
    ).splitlines():
        fields = line.split("\t")
        if len(fields) == 3:
            weights[fields[0]] = int(fields[2])
    assert weights["常"] > weights["僻"]
    ranking = manifest["single_character_ranking"]
    assert ranking["core_distinct_characters"] == 1
    assert ranking["peripheral_distinct_characters"] == 1
    assert ranking["core_above_peripheral"] is True
    assert manifest["production_intersection"][
        "retained_formal_single_readings_without_production_match"
    ] == 1


def test_character_coverage_gate_requires_every_character_and_reading() -> None:
    policy = {
        "expected_distinct_characters": 2,
        "expected_source_reading_entries": 3,
    }
    complete = {
        "allowed_encoded_hanzi": 2,
        "distinct_texts_by_length": {"1": 2},
        "reading_entries_by_length": {"1": 3},
    }
    assert _assert_character_boundary(
        complete,
        policy,
        label="test",
        expected_readings_field="expected_source_reading_entries",
    ) == {
        "distinct_characters": 2,
        "reading_entries": 3,
    }

    for field, incomplete in (
        (
            "character",
            {
                **complete,
                "distinct_texts_by_length": {"1": 1},
            },
        ),
        (
            "reading",
            {
                **complete,
                "reading_entries_by_length": {"1": 2},
            },
        ),
    ):
        with pytest.raises(ValueError, match=field):
            _assert_character_boundary(
                incomplete,
                policy,
                label="test",
                expected_readings_field="expected_source_reading_entries",
            )
