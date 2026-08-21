from __future__ import annotations

import sqlite3


MATERIALIZED_COLUMNS = (
    "entry_type",
    "entry_id",
    "text",
    "pinyin_tone",
    "yime_code",
    "full_yime_code",
    "primary_yime_code",
    "variable_yinyuan_code",
    "input_shorthand_code",
    "sort_weight",
    "is_common",
    "text_length",
    "updated_at",
)


def _create_materialized_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE runtime_candidates_materialized (
            entry_type TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_tone TEXT NOT NULL,
            yime_code TEXT NOT NULL,
            full_yime_code TEXT NOT NULL DEFAULT '',
            primary_yime_code TEXT NOT NULL DEFAULT '',
            variable_yinyuan_code TEXT NOT NULL DEFAULT '',
            input_shorthand_code TEXT NOT NULL DEFAULT '',
            sort_weight REAL NOT NULL,
            is_common INTEGER NOT NULL,
            text_length INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (entry_type, entry_id, pinyin_tone)
        )
        """
    )


def ensure_materialized_runtime_candidate_table(conn: sqlite3.Connection) -> None:
    """Allow one lexicon entry to expose multiple reviewed pronunciation codes."""
    table_exists = conn.execute(
        """
        SELECT 1 FROM sqlite_master
        WHERE type = 'table' AND name = 'runtime_candidates_materialized'
        """
    ).fetchone()
    if table_exists is None:
        _create_materialized_table(conn)
        return

    columns = {
        str(row[1])
        for row in conn.execute(
            "PRAGMA table_info(runtime_candidates_materialized)"
        ).fetchall()
    }
    additions = {
        "full_yime_code": "TEXT NOT NULL DEFAULT ''",
        "primary_yime_code": "TEXT NOT NULL DEFAULT ''",
        "variable_yinyuan_code": "TEXT NOT NULL DEFAULT ''",
        "input_shorthand_code": "TEXT NOT NULL DEFAULT ''",
    }
    for column_name, column_spec in additions.items():
        if column_name not in columns:
            conn.execute(
                f"ALTER TABLE runtime_candidates_materialized "
                f"ADD COLUMN {column_name} {column_spec}"
            )

    table_info = conn.execute(
        "PRAGMA table_info(runtime_candidates_materialized)"
    ).fetchall()
    primary_key = tuple(
        str(row[1])
        for row in sorted(
            (row for row in table_info if int(row[5]) > 0),
            key=lambda row: int(row[5]),
        )
    )
    if primary_key == ("entry_type", "entry_id", "pinyin_tone"):
        return

    legacy_table = "runtime_candidates_materialized__single_reading"
    conn.execute(f"DROP TABLE IF EXISTS {legacy_table}")
    conn.execute(
        f"ALTER TABLE runtime_candidates_materialized RENAME TO {legacy_table}"
    )
    _create_materialized_table(conn)
    column_list = ", ".join(MATERIALIZED_COLUMNS)
    conn.execute(
        f"INSERT INTO runtime_candidates_materialized ({column_list}) "
        f"SELECT {column_list} FROM {legacy_table}"
    )
    conn.execute(f"DROP TABLE {legacy_table}")
