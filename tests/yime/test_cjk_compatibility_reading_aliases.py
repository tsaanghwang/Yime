from __future__ import annotations

import sqlite3

from external_data.unihan_readings.mandarin_readings_supplement import (
    apply_compatibility_reading_aliases,
)


ALIASES = {
    "U+F9E7": "U+88CF",
    "U+F92C": "U+90CE",
    "U+F979": "U+51C9",
    "U+F9F1": "U+96A3",
    "U+FA0C": "U+5140",
    "U+FA0D": "U+55C0",
    "U+FA20": "U+8612",
}


def test_compatibility_aliases_copy_target_readings_without_defining_pinyin() -> None:
    connection = sqlite3.connect(":memory:")
    connection.executescript(
        """
        CREATE TABLE hanzi (
            codepoint TEXT PRIMARY KEY,
            hanzi TEXT NOT NULL
        );
        CREATE TABLE mandarin_readings_merged (
            codepoint TEXT PRIMARY KEY,
            hanzi TEXT NOT NULL,
            readings TEXT,
            common_reading TEXT,
            common_reading_source TEXT,
            is_single INTEGER NOT NULL
        );
        """
    )
    for index, (alias, target) in enumerate(ALIASES.items(), start=1):
        connection.execute(
            "INSERT INTO hanzi VALUES (?, ?)",
            (alias, chr(int(alias[2:], 16))),
        )
        connection.execute(
            "INSERT INTO hanzi VALUES (?, ?)",
            (target, chr(int(target[2:], 16))),
        )
        reading = f"test{index}"
        connection.execute(
            """
            INSERT INTO mandarin_readings_merged
            VALUES (?, ?, ?, ?, 'test-source', 1)
            """,
            (target, chr(int(target[2:], 16)), reading, reading),
        )

    assert apply_compatibility_reading_aliases(connection.cursor()) == list(
        ALIASES
    )
    for alias, target in ALIASES.items():
        alias_row = connection.execute(
            """
            SELECT readings, common_reading, common_reading_source
            FROM mandarin_readings_merged
            WHERE codepoint = ?
            """,
            (alias,),
        ).fetchone()
        target_row = connection.execute(
            """
            SELECT readings, common_reading
            FROM mandarin_readings_merged
            WHERE codepoint = ?
            """,
            (target,),
        ).fetchone()
        assert alias_row[:2] == target_row
        assert alias_row[2] == f"compatibility_alias:{target}"
