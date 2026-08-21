import importlib.util
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
REFRESH_SCRIPT = WORKSPACE_ROOT / "tools" / "refresh_materialized_syllable_inventory.py"

_refresh_spec = importlib.util.spec_from_file_location(
    "refresh_materialized_syllable_inventory",
    REFRESH_SCRIPT,
)
if _refresh_spec is None or _refresh_spec.loader is None:
    raise ImportError("Could not load refresh_materialized_syllable_inventory module")
_refresh_module = importlib.util.module_from_spec(_refresh_spec)
_refresh_spec.loader.exec_module(_refresh_module)

rebuild_analysis_views = _refresh_module.rebuild_analysis_views
refresh_materialized_table = _refresh_module.refresh_materialized_table


def _build_inventory(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE m_distinct_syllable_inventory (
            numeric_syllable TEXT NOT NULL,
            marked_syllable TEXT NOT NULL,
            source_tables TEXT NOT NULL,
            has_single_char INTEGER NOT NULL,
            has_phrase INTEGER NOT NULL,
            single_char_distinct_count INTEGER NOT NULL,
            phrase_distinct_count INTEGER NOT NULL,
            flattened_distinct_count INTEGER NOT NULL,
            PRIMARY KEY (numeric_syllable, marked_syllable)
        ) WITHOUT ROWID;

        INSERT INTO m_distinct_syllable_inventory VALUES
            ('ng5', 'ng', 'single_char', 1, 0, 1, 0, 1),
            ('hng5', 'hng', 'single_char', 1, 0, 1, 0, 1),
            ('m2', 'ḿ', 'single_char', 1, 0, 1, 0, 1),
            ('ma3', 'mǎ', 'single_char,phrase', 1, 1, 1, 1, 2);
        """
    )
    rebuild_analysis_views(connection, "m_distinct_syllable_inventory")


def test_special_syllable_numeric_finals_keep_numeric_tones() -> None:
    connection = sqlite3.connect(":memory:")
    try:
        _build_inventory(connection)
        rows = {
            numeric: (numeric_final, tone_final)
            for numeric, numeric_final, tone_final in connection.execute(
                """
                SELECT original_numeric_syllable,
                       current_rule_numeric_final,
                       current_rule_tone_final
                FROM v_syllable_split_current_rule
                WHERE original_numeric_syllable IN ('ng5', 'hng5', 'm2')
                """
            )
        }
    finally:
        connection.close()

    assert rows == {
        "ng5": ("ng5", "ng"),
        "hng5": ("ng5", "ng"),
        "m2": ("m2", "ḿ"),
    }


def test_current_rule_exposes_final_base_and_numeric_tone() -> None:
    connection = sqlite3.connect(":memory:")
    try:
        _build_inventory(connection)
        rows = {
            numeric: (numeric_final, final_base, tone_number)
            for numeric, numeric_final, final_base, tone_number in connection.execute(
                """
                SELECT original_numeric_syllable,
                       current_rule_numeric_final,
                       current_rule_final_base,
                       current_rule_tone_number
                FROM v_syllable_split_current_rule
                ORDER BY original_numeric_syllable
                """
            )
        }
        missing_tones = connection.execute(
            """
            SELECT COUNT(*)
            FROM v_syllable_split_current_rule
            WHERE current_rule_tone_number IS NULL
            """
        ).fetchone()[0]
    finally:
        connection.close()

    assert rows == {
        "hng5": ("ng5", "ng", 5),
        "m2": ("m2", "m", 2),
        "ma3": ("a3", "a", 3),
        "ng5": ("ng5", "ng", 5),
    }
    assert missing_tones == 0


def test_candidate_only_phrase_reading_contributes_syllables() -> None:
    connection = sqlite3.connect(":memory:")
    try:
        connection.executescript(
            """
            CREATE TABLE char_readings (
                numeric_pinyin TEXT,
                marked_pinyin TEXT
            );
            CREATE TABLE phrase_candidate_readings (
                id INTEGER PRIMARY KEY,
                numeric_pinyin TEXT,
                marked_pinyin TEXT
            );
            INSERT INTO phrase_candidate_readings VALUES
                (1, 'da3 dian3', 'dǎ diǎn'),
                (2, 'da3 dian5', 'dǎ dian');
            """
        )
        count = refresh_materialized_table(
            connection,
            "m_distinct_syllable_inventory",
        )
        rows = {
            tuple(row)
            for row in connection.execute(
                "SELECT numeric_syllable, marked_syllable "
                "FROM m_distinct_syllable_inventory"
            )
        }
    finally:
        connection.close()

    assert count == 3
    assert ("dian3", "diǎn") in rows
    assert ("dian5", "dian") in rows
