from __future__ import annotations

import sqlite3

from yime.utils.runtime_candidates_export import normalize_sort_weight_for_export
from yime.utils.runtime_candidates_export import build_candidate_record, group_rows
from yime.utils.runtime_codes_refresh import rebuild_materialized_runtime_candidates


def test_normalize_sort_weight_for_export_rounds_binary_tail() -> None:
    assert normalize_sort_weight_for_export(3.7152000000000003) == 3.7152


def test_normalize_sort_weight_for_export_keeps_integer_weight_stable() -> None:
    assert normalize_sort_weight_for_export(120) == 120.0


def test_build_candidate_record_keeps_primary_yime_code() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        """
        SELECT
            '啊' AS text,
            'char' AS entry_type,
            '1' AS entry_id,
            'a1' AS pinyin_tone,
            'ABCD' AS yime_code,
            'ABCD' AS full_yime_code,
            'AB' AS primary_yime_code,
            'AB' AS variable_yinyuan_code,
            'A' AS input_shorthand_code,
            1.0 AS sort_weight,
            1 AS is_common,
            1 AS text_length,
            '2026-06-25' AS updated_at
        """
    ).fetchone()

    record = build_candidate_record(row)

    assert record["yime_code"] == "ABCD"
    assert record["full_yime_code"] == "ABCD"
    assert record["primary_yime_code"] == "AB"
    assert record["variable_yinyuan_code"] == "AB"
    assert record["input_shorthand_code"] == "A"
    conn.close()


def test_group_rows_prefers_primary_yime_code() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        """
        SELECT
            '啊' AS text,
            'char' AS entry_type,
            '1' AS entry_id,
            'a1' AS pinyin_tone,
            'ABCD' AS yime_code,
            'ABCD' AS full_yime_code,
            'AB' AS primary_yime_code,
            'AB' AS variable_yinyuan_code,
            'A' AS input_shorthand_code,
            1.0 AS sort_weight,
            1 AS is_common,
            1 AS text_length,
            '2026-06-25' AS updated_at
        """
    ).fetchone()

    grouped = group_rows([row], limit_per_code=0)

    assert list(grouped) == ["AB"]
    assert grouped["AB"][0]["yime_code"] == "ABCD"
    conn.close()


def test_materialized_runtime_candidates_store_primary_yime_code_and_match_export_grouping() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE runtime_candidates (
            entry_type TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_tone TEXT NOT NULL,
            yime_code TEXT NOT NULL,
            sort_weight REAL NOT NULL,
            is_common INTEGER NOT NULL,
            text_length INTEGER NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE runtime_candidates_materialized (
            entry_type TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_tone TEXT NOT NULL,
            yime_code TEXT NOT NULL,
            sort_weight REAL NOT NULL,
            is_common INTEGER NOT NULL,
            text_length INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (entry_type, entry_id)
        );
        """
    )
    conn.execute(
        """
        INSERT INTO runtime_candidates (
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("char", "1", "啊", "a1", "􀀋􀀩􀀩􀀩", 1.0, 1, 1, "2026-06-25"),
    )

    rebuilt_rows = rebuild_materialized_runtime_candidates(conn)
    materialized = conn.execute(
        """
        SELECT
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            full_yime_code,
            primary_yime_code,
            variable_yinyuan_code,
            input_shorthand_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        FROM runtime_candidates_materialized
        """
    ).fetchall()
    grouped = group_rows(materialized, limit_per_code=0)

    assert rebuilt_rows == 1
    assert len(materialized) == 1
    assert materialized[0]["yime_code"] == "􀀋􀀩􀀩􀀩"
    assert materialized[0]["full_yime_code"] == "􀀋􀀩􀀩􀀩"
    expected_derived_code = "􀀋􀀩"
    assert materialized[0]["primary_yime_code"] == expected_derived_code
    assert materialized[0]["variable_yinyuan_code"] == expected_derived_code
    assert materialized[0]["input_shorthand_code"] == expected_derived_code
    assert list(grouped) == [expected_derived_code]
    conn.close()


def test_materialized_runtime_candidates_allow_multiple_readings_for_one_phrase() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE runtime_candidates (
            entry_type TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_tone TEXT NOT NULL,
            yime_code TEXT NOT NULL,
            sort_weight REAL NOT NULL,
            is_common INTEGER NOT NULL,
            text_length INTEGER NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE runtime_candidates_materialized (
            entry_type TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_tone TEXT NOT NULL,
            yime_code TEXT NOT NULL,
            sort_weight REAL NOT NULL,
            is_common INTEGER NOT NULL,
            text_length INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (entry_type, entry_id)
        );
        """
    )
    conn.executemany(
        "INSERT INTO runtime_candidates VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            ("phrase", "7", "当天", "dang4 tian1", "ABCD", 10.0, 1, 2, "now"),
            ("phrase", "7", "当天", "dang1 tian1", "WXYZ", 10.0, 1, 2, "now"),
        ],
    )

    assert rebuild_materialized_runtime_candidates(conn) == 2
    assert [
        row[0]
        for row in conn.execute(
            "SELECT pinyin_tone FROM runtime_candidates_materialized ORDER BY pinyin_tone"
        )
    ] == ["dang1 tian1", "dang4 tian1"]
    primary_key = tuple(
        row[1]
        for row in sorted(
            (
                row
                for row in conn.execute(
                    "PRAGMA table_info(runtime_candidates_materialized)"
                )
                if row[5]
            ),
            key=lambda row: row[5],
        )
    )
    assert primary_key == ("entry_type", "entry_id", "pinyin_tone")
    conn.close()
