from __future__ import annotations

import sqlite3
from pathlib import Path

from yime.canonical_yime_mapping import load_code_mode_map
from yime.utils.rime_export import (
    convert_runtime_code_to_layout_keys,
    load_runtime_symbol_to_layout_key,
)
from yime.utils.runtime_lexicon_selection import (
    apply_runtime_selection,
    disable_runtime_selection,
)


def _prepare_runtime_database(path: Path) -> tuple[str, str]:
    code_map = load_code_mode_map()
    first_code = code_map["jia3"].full_code
    second_code = code_map["yi3"].full_code
    connection = sqlite3.connect(path)
    try:
        connection.executescript(
            """
            CREATE TABLE prototype_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                note TEXT,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
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
                full_yime_code TEXT NOT NULL DEFAULT '',
                primary_yime_code TEXT NOT NULL DEFAULT '',
                variable_yinyuan_code TEXT NOT NULL DEFAULT '',
                input_shorthand_code TEXT NOT NULL DEFAULT '',
                sort_weight REAL NOT NULL,
                is_common INTEGER NOT NULL,
                text_length INTEGER NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (entry_type, entry_id)
            );
            """
        )
        connection.executemany(
            """
            INSERT INTO runtime_candidates
            VALUES ('char', ?, ?, ?, ?, ?, 1, 1, CURRENT_TIMESTAMP)
            """,
            (
                ("1", "甲", "jia3", first_code, 10.0),
                ("2", "乙", "yi3", second_code, 9.0),
            ),
        )
        connection.commit()
    finally:
        connection.close()
    return first_code, second_code


def test_selection_overlay_filters_only_materialized_candidates(
    tmp_path: Path,
) -> None:
    database = tmp_path / "runtime.db"
    first_code, _second_code = _prepare_runtime_database(database)
    selection = tmp_path / "selection.tsv"
    layout_code = convert_runtime_code_to_layout_keys(
        first_code,
        load_runtime_symbol_to_layout_key(),
    )
    selection.write_text(
        "text\tfull_layout_code\tweight\tselection_level"
        "\tselection_reason\n"
        f"甲\t{layout_code}\t10\tfirst_level\tfixture\n",
        encoding="utf-8",
    )

    payload = apply_runtime_selection(database, selection)

    assert payload["materialized_runtime_rows"] == 1
    with sqlite3.connect(database) as connection:
        assert connection.execute(
            "SELECT text FROM runtime_candidates_materialized"
        ).fetchall() == [("甲",)]
        assert connection.execute(
            "SELECT COUNT(*) FROM runtime_candidates"
        ).fetchone()[0] == 2

    assert disable_runtime_selection(database) == 2
    with sqlite3.connect(database) as connection:
        assert {
            row[0]
            for row in connection.execute(
                "SELECT text FROM runtime_candidates_materialized"
            )
        } == {"甲", "乙"}


def test_unmatched_selected_reading_fails_without_changing_overlay(
    tmp_path: Path,
) -> None:
    database = tmp_path / "runtime.db"
    _prepare_runtime_database(database)
    selection = tmp_path / "selection.tsv"
    selection.write_text(
        "text\tfull_layout_code\tweight\tselection_level"
        "\tselection_reason\n"
        "丙\tAAAA\t1\tfirst_level\tfixture\n",
        encoding="utf-8",
    )

    try:
        apply_runtime_selection(database, selection)
    except ValueError as exc:
        assert "absent from the runtime inventory" in str(exc)
    else:
        raise AssertionError("unmatched selection should fail")

    with sqlite3.connect(database) as connection:
        assert connection.execute(
            "SELECT COUNT(*) FROM runtime_lexicon_selection"
        ).fetchone()[0] == 0
