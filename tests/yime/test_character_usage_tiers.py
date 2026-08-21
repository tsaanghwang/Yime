from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from yime.lexicon_bundle.character_tiers import TIER_NAMES
from yime.utils.runtime_codes_refresh import build_char_usage_profile_rows


def _build_unified_tier_db(path: Path) -> None:
    with sqlite3.connect(path) as connection:
        connection.execute(
            """
            CREATE TABLE character_tiers (
                hanzi TEXT NOT NULL,
                tier_number INTEGER NOT NULL,
                tier_name TEXT NOT NULL,
                tier_rank INTEGER NOT NULL,
                membership_source TEXT NOT NULL,
                encoded_reading_count INTEGER NOT NULL
            )
            """
        )
        connection.executemany(
            "INSERT INTO character_tiers VALUES (?, ?, ?, ?, ?, ?)",
            (
                ("甲", 1, TIER_NAMES[1], 1, "kTGH", 1),
                ("乙", 5, TIER_NAMES[5], 1, "BCC cap", 1),
                ("丙", 8, TIER_NAMES[8], 1, "project encoded", 1),
                ("丁", 9, TIER_NAMES[9], 1, "unencoded", 0),
            ),
        )


def test_runtime_usage_profile_only_copies_unified_encoded_tiers(
    tmp_path: Path,
) -> None:
    source_db = tmp_path / "source_lexicon.sqlite3"
    _build_unified_tier_db(source_db)

    runtime = sqlite3.connect(":memory:")
    runtime.execute(
        "CREATE TABLE char_inventory (hanzi TEXT, char_frequency_abs INTEGER)"
    )
    runtime.executemany(
        "INSERT INTO char_inventory VALUES (?, ?)",
        (("甲", 100), ("乙", 50), ("丙", 1)),
    )

    rows = build_char_usage_profile_rows(
        runtime,
        source_db_path=source_db,
    )
    assert [row[0] for row in rows] == ["甲", "乙", "丙"]
    assert [row[1] for row in rows] == [
        TIER_NAMES[1],
        TIER_NAMES[5],
        TIER_NAMES[8],
    ]
    assert rows[0][3] > rows[1][3] > rows[2][3]
    assert all(row[4].startswith("unified_source_character_tiers:") for row in rows)


def test_runtime_usage_profile_rejects_inventory_outside_unified_tiers(
    tmp_path: Path,
) -> None:
    source_db = tmp_path / "source_lexicon.sqlite3"
    _build_unified_tier_db(source_db)

    runtime = sqlite3.connect(":memory:")
    runtime.execute(
        "CREATE TABLE char_inventory (hanzi TEXT, char_frequency_abs INTEGER)"
    )
    runtime.executemany(
        "INSERT INTO char_inventory VALUES (?, ?)",
        (("甲", 100), ("缺", 1)),
    )

    with pytest.raises(RuntimeError, match="missing=1"):
        build_char_usage_profile_rows(
            runtime,
            source_db_path=source_db,
        )
