from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.asset_paths import resolve_lexicon_source_db_path  # noqa: E402

# cspell:ignore zcsr jqxy uēng uéng uěng uèng

SOURCE_DB_PATH = resolve_lexicon_source_db_path(ROOT)
DEFAULT_TABLE_NAME = "m_distinct_syllable_inventory"

# Inline flattening: char_readings rows + phrase_readings split by spaces.
# Original workflow materialized directly; no persistent v_flat_distinct_syllables view.
_FLAT_SYLLABLES_CTE = """
        WITH RECURSIVE phrase_syllable_split AS (
            SELECT
                id,
                1 AS syllable_index,
                TRIM(
                    SUBSTR(
                        numeric_pinyin || ' ',
                        1,
                        INSTR(numeric_pinyin || ' ', ' ') - 1
                    )
                ) AS numeric_syllable,
                TRIM(
                    SUBSTR(
                        marked_pinyin || ' ',
                        1,
                        INSTR(marked_pinyin || ' ', ' ') - 1
                    )
                ) AS marked_syllable,
                TRIM(
                    SUBSTR(
                        numeric_pinyin || ' ',
                        INSTR(numeric_pinyin || ' ', ' ') + 1
                    )
                ) AS rest_numeric,
                TRIM(
                    SUBSTR(
                        marked_pinyin || ' ',
                        INSTR(marked_pinyin || ' ', ' ') + 1
                    )
                ) AS rest_marked
            FROM phrase_candidate_readings
            WHERE TRIM(COALESCE(numeric_pinyin, '')) <> ''
              AND TRIM(COALESCE(marked_pinyin, '')) <> ''

            UNION ALL

            SELECT
                id,
                syllable_index + 1,
                TRIM(
                    SUBSTR(
                        rest_numeric || ' ',
                        1,
                        INSTR(rest_numeric || ' ', ' ') - 1
                    )
                ),
                TRIM(
                    SUBSTR(
                        rest_marked || ' ',
                        1,
                        INSTR(rest_marked || ' ', ' ') - 1
                    )
                ),
                TRIM(
                    SUBSTR(
                        rest_numeric || ' ',
                        INSTR(rest_numeric || ' ', ' ') + 1
                    )
                ),
                TRIM(
                    SUBSTR(
                        rest_marked || ' ',
                        INSTR(rest_marked || ' ', ' ') + 1
                    )
                )
            FROM phrase_syllable_split
            WHERE rest_numeric <> ''
        ),
        flat_distinct_syllables AS (
            SELECT
                numeric_pinyin AS numeric_syllable,
                marked_pinyin AS marked_syllable,
                'single_char' AS source_table
            FROM char_readings
            WHERE TRIM(COALESCE(numeric_pinyin, '')) <> ''
              AND TRIM(COALESCE(marked_pinyin, '')) <> ''

            UNION ALL

            SELECT
                numeric_syllable,
                marked_syllable,
                'phrase' AS source_table
            FROM phrase_syllable_split
            WHERE TRIM(COALESCE(numeric_syllable, '')) <> ''
              AND TRIM(COALESCE(marked_syllable, '')) <> ''
        ),
"""

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="把统一 source_lexicon.sqlite3 中的音节库存物化成独立表。"
    )
    parser.add_argument(
        "--db-path",
        type=Path,
        default=SOURCE_DB_PATH,
        help="统一 source_lexicon.sqlite3 路径，默认使用仓库生成路径。",
    )
    parser.add_argument(
        "--table-name",
        default=DEFAULT_TABLE_NAME,
        help=f"物化表名，默认 {DEFAULT_TABLE_NAME}。",
    )
    parser.add_argument(
        "--views-only",
        action="store_true",
        help="Skip rebuilding the materialized table and only recreate dependent analysis views.",
    )
    return parser.parse_args()


def quote_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def refresh_materialized_table(connection: sqlite3.Connection, table_name: str) -> int:
    quoted_table = quote_identifier(table_name)
    marked_index = quote_identifier(f"idx_{table_name}_marked_syllable")
    source_index = quote_identifier(f"idx_{table_name}_source_flags")

    connection.executescript(
        f"""
        DROP VIEW IF EXISTS v_flat_distinct_syllables;

        DROP TABLE IF EXISTS {quoted_table};

        CREATE TABLE {quoted_table} (
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

        INSERT INTO {quoted_table} (
            numeric_syllable,
            marked_syllable,
            source_tables,
            has_single_char,
            has_phrase,
            single_char_distinct_count,
            phrase_distinct_count,
            flattened_distinct_count
        )
        {_FLAT_SYLLABLES_CTE}
        syllable_usage AS (
            SELECT
                numeric_syllable,
                marked_syllable,
                MAX(CASE WHEN source_table = 'single_char' THEN 1 ELSE 0 END) AS has_single_char,
                MAX(CASE WHEN source_table = 'phrase' THEN 1 ELSE 0 END) AS has_phrase,
                SUM(CASE WHEN source_table = 'single_char' THEN 1 ELSE 0 END) AS single_char_distinct_count,
                SUM(CASE WHEN source_table = 'phrase' THEN 1 ELSE 0 END) AS phrase_distinct_count,
                COUNT(*) AS flattened_distinct_count
            FROM flat_distinct_syllables
            WHERE TRIM(COALESCE(numeric_syllable, '')) <> ''
              AND TRIM(COALESCE(marked_syllable, '')) <> ''
            GROUP BY numeric_syllable, marked_syllable
        )
        SELECT
            numeric_syllable,
            marked_syllable,
            CASE
                WHEN has_single_char = 1 AND has_phrase = 1 THEN 'single_char,phrase'
                WHEN has_single_char = 1 THEN 'single_char'
                ELSE 'phrase'
            END AS source_tables,
            has_single_char,
            has_phrase,
            single_char_distinct_count,
            phrase_distinct_count,
            flattened_distinct_count
        FROM syllable_usage
        ORDER BY numeric_syllable, marked_syllable;

        CREATE INDEX {marked_index}
        ON {quoted_table} (marked_syllable);

        CREATE INDEX {source_index}
        ON {quoted_table} (has_single_char, has_phrase);
        """
    )

    return connection.execute(
        f"SELECT COUNT(*) FROM {quoted_table}"
    ).fetchone()[0]


def rebuild_analysis_views(connection: sqlite3.Connection, table_name: str) -> None:
        quoted_table = quote_identifier(table_name)

        connection.executescript(
                f"""
                DROP VIEW IF EXISTS v_syllable_split_audit;
                DROP VIEW IF EXISTS v_syllable_split_current_rule;
                DROP VIEW IF EXISTS v_syllable_splitter_current_rule;
                DROP VIEW IF EXISTS v_numeric_syllable_marked_conflicts;
                DROP VIEW IF EXISTS v_distinct_syllable_inventory;

                CREATE VIEW v_distinct_syllable_inventory AS
                SELECT
                    numeric_syllable,
                    marked_syllable
                FROM {quoted_table};

                CREATE VIEW v_numeric_syllable_marked_conflicts AS
                SELECT
                    numeric_syllable,
                    COUNT(DISTINCT marked_syllable) AS marked_variant_count,
                    GROUP_CONCAT(DISTINCT marked_syllable) AS marked_syllable_variants
                FROM {quoted_table}
                GROUP BY numeric_syllable
                HAVING COUNT(DISTINCT marked_syllable) > 1;

                CREATE VIEW v_syllable_split_current_rule AS
                WITH inventory AS (
                    SELECT numeric_syllable, marked_syllable FROM {quoted_table}
                ),
                source_usage AS (
                    SELECT
                        numeric_syllable,
                        marked_syllable,
                        source_tables,
                        flattened_distinct_count AS flattened_row_count,
                        has_single_char,
                        has_phrase,
                        single_char_distinct_count,
                        phrase_distinct_count
                    FROM {quoted_table}
                ),
                numeric_split AS (
                    SELECT
                        i.numeric_syllable,
                        i.marked_syllable,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN 'special_syllable'
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e','ê') THEN 'zero_initial_vowel'
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') AND LENGTH(i.numeric_syllable) > 2 AND SUBSTR(i.numeric_syllable, 3, 1) = 'i' THEN 'zh_ch_sh_tongue_tip_i'
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') AND NOT (LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'ui[1-5]' OR LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'un[1-5]') THEN 'zh_ch_sh'
                            WHEN SUBSTR(LOWER(i.numeric_syllable), 1, 1) IN ('z','c','s','r') AND LENGTH(i.numeric_syllable) > 1 AND SUBSTR(i.numeric_syllable, 2, 1) = 'i' THEN 'zcsr_tongue_tip_i'
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) IN ('j','q','x','y') AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN 'jqxy_u_to_umlaut'
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'yong_cuokou_placeholder'
                            WHEN LOWER(i.numeric_syllable) GLOB 'ya*' OR LOWER(i.numeric_syllable) GLOB 'ye*' OR LOWER(i.numeric_syllable) GLOB 'you*' OR (LOWER(i.numeric_syllable) GLOB 'yo*' AND LOWER(i.numeric_syllable) NOT GLOB 'yong*') THEN 'y_standard_restored_final'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei*' OR LOWER(i.numeric_syllable) GLOB 'wen*' OR LOWER(i.numeric_syllable) GLOB 'weng*' OR LOWER(i.numeric_syllable) GLOB 'wai*' OR LOWER(i.numeric_syllable) GLOB 'wan*' OR LOWER(i.numeric_syllable) GLOB 'wang*' OR LOWER(i.numeric_syllable) GLOB 'wa*' OR (LOWER(i.numeric_syllable) GLOB 'wo*' AND LOWER(i.numeric_syllable) NOT GLOB 'wong*') THEN 'w_standard_restored_final'
                            WHEN (LOWER(i.numeric_syllable) GLOB '*iu[1-5]' AND LOWER(i.numeric_syllable) NOT GLOB 'you*') OR LOWER(i.numeric_syllable) GLOB '*ui[1-5]' OR LOWER(i.numeric_syllable) GLOB '*un[1-5]' THEN 'general_standard_restored_final'
                            ELSE 'default_first_char'
                        END AS numeric_matched_rule,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN ''''
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e','ê') THEN ''''
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') THEN LOWER(SUBSTR(i.numeric_syllable, 1, 2))
                            WHEN SUBSTR(LOWER(i.numeric_syllable), 1, 1) IN ('z','c','s','r') AND LENGTH(i.numeric_syllable) > 1 AND SUBSTR(i.numeric_syllable, 2, 1) = 'i' THEN LOWER(SUBSTR(i.numeric_syllable, 1, 1))
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) IN ('j','q','x') AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN SUBSTR(i.numeric_syllable, 1, 1)
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) = 'y' AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN 'ɥ'
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'ɥ'
                            ELSE SUBSTR(i.numeric_syllable, 1, 1)
                        END AS current_rule_initial,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN i.numeric_syllable
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e','ê') THEN i.numeric_syllable
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') AND LENGTH(i.numeric_syllable) > 2 AND SUBSTR(i.numeric_syllable, 3, 1) = 'i' THEN '_' || SUBSTR(i.numeric_syllable, 3)
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') AND NOT (LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'ui[1-5]' OR LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'un[1-5]') THEN SUBSTR(i.numeric_syllable, 3)
                            WHEN SUBSTR(LOWER(i.numeric_syllable), 1, 1) IN ('z','c','s','r') AND LENGTH(i.numeric_syllable) > 1 AND SUBSTR(i.numeric_syllable, 2, 1) = 'i' THEN '_' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) IN ('j','q','x','y') AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN 'ü' || SUBSTR(i.numeric_syllable, 3)
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'iong' || SUBSTR(i.numeric_syllable, 5)
                            WHEN LOWER(i.numeric_syllable) GLOB 'you*' THEN 'iou' || SUBSTR(i.numeric_syllable, 4)
                            WHEN LOWER(i.numeric_syllable) GLOB 'ya*' THEN 'i' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'ye*' THEN 'i' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'yo*' AND LOWER(i.numeric_syllable) NOT GLOB 'yong*' THEN 'io' || SUBSTR(i.numeric_syllable, 3)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei*' THEN 'uei' || SUBSTR(i.numeric_syllable, 4)
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng*' THEN 'ueng' || SUBSTR(i.numeric_syllable, 5)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wang*' THEN 'uang' || SUBSTR(i.numeric_syllable, 5)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen*' THEN 'uen' || SUBSTR(i.numeric_syllable, 4)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wai*' THEN 'uai' || SUBSTR(i.numeric_syllable, 4)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wan*' THEN 'uan' || SUBSTR(i.numeric_syllable, 4)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wa*' THEN 'u' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wo*' AND LOWER(i.numeric_syllable) NOT GLOB 'wong*' THEN 'u' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu[1-5]' AND LOWER(i.numeric_syllable) NOT GLOB 'you*' THEN 'iou' || SUBSTR(i.numeric_syllable, -1)
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui[1-5]' THEN 'uei' || SUBSTR(i.numeric_syllable, -1)
                            WHEN LOWER(i.numeric_syllable) GLOB '*un[1-5]' THEN 'uen' || SUBSTR(i.numeric_syllable, -1)
                            ELSE CASE WHEN LENGTH(i.numeric_syllable) > 1 THEN SUBSTR(i.numeric_syllable, 2) ELSE '' END
                        END AS current_rule_numeric_final,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN ''''
                            WHEN i.numeric_syllable GLOB 'zh*' OR i.numeric_syllable GLOB 'ch*' OR i.numeric_syllable GLOB 'sh*' THEN SUBSTR(i.numeric_syllable, 1, 2)
                            WHEN i.numeric_syllable IN ('ri1','ri2','ri3','ri4','ri5','zi1','zi2','zi3','zi4','zi5','ci1','ci2','ci3','ci4','ci5','si1','si2','si3','si4','si5') THEN SUBSTR(i.numeric_syllable, 1, 1)
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e') OR i.numeric_syllable GLOB 'ê*' THEN ''''
                            WHEN i.numeric_syllable GLOB 'yu*' THEN 'ɥ'
                            WHEN i.numeric_syllable GLOB 'yong*' THEN 'ɥ'
                            ELSE SUBSTR(i.numeric_syllable, 1, 1)
                        END AS expected_initial_hint
                    FROM inventory i
                ),
                tone_split AS (
                    SELECT
                        i.numeric_syllable,
                        i.marked_syllable,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN 'special_syllable'
                            WHEN SUBSTR(i.marked_syllable, 1, 1) IN ('a','o','e','ê','ā','ō','ē','ế','à','ò','è','ǎ','ǒ','ě','á','ó','é') THEN 'zero_initial_vowel'
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 2)) IN ('zh','ch','sh') AND LENGTH(i.marked_syllable) > 2 AND SUBSTR(i.marked_syllable, 3, 1) IN ('i','ī','í','ǐ','ì') THEN 'zh_ch_sh_tongue_tip_i'
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 2)) IN ('zh','ch','sh') AND NOT (LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'ui[1-5]' OR LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'un[1-5]') THEN 'zh_ch_sh'
                            WHEN SUBSTR(LOWER(i.marked_syllable), 1, 1) IN ('z','c','s','r') AND LENGTH(i.marked_syllable) > 1 AND SUBSTR(i.marked_syllable, 2, 1) IN ('i','ī','í','ǐ','ì') THEN 'zcsr_tongue_tip_i'
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 1)) IN ('j','q','x') AND SUBSTR(i.marked_syllable, 2, 1) IN ('u','ū','ú','ǔ','ù','ü','ǖ','ǘ','ǚ','ǜ') THEN 'jqx_umlaut_family'
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 1)) = 'y' AND SUBSTR(i.marked_syllable, 2, 1) IN ('u','ū','ú','ǔ','ù','ü','ǖ','ǘ','ǚ','ǜ') THEN 'yu_umlaut_family'
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'yong_cuokou_placeholder'
                            WHEN LOWER(i.numeric_syllable) GLOB 'ya*' OR LOWER(i.numeric_syllable) GLOB 'ye*' OR LOWER(i.numeric_syllable) GLOB 'you*' OR (LOWER(i.numeric_syllable) GLOB 'yo*' AND LOWER(i.numeric_syllable) NOT GLOB 'yong*') THEN 'y_standard_restored_final'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei*' OR LOWER(i.numeric_syllable) GLOB 'wen*' OR LOWER(i.numeric_syllable) GLOB 'weng*' OR LOWER(i.numeric_syllable) GLOB 'wai*' OR LOWER(i.numeric_syllable) GLOB 'wan*' OR LOWER(i.numeric_syllable) GLOB 'wang*' OR LOWER(i.numeric_syllable) GLOB 'wa*' OR (LOWER(i.numeric_syllable) GLOB 'wo*' AND LOWER(i.numeric_syllable) NOT GLOB 'wong*') THEN 'w_standard_restored_final'
                            WHEN (LOWER(i.numeric_syllable) GLOB '*iu[1-5]' AND LOWER(i.numeric_syllable) NOT GLOB 'you*') OR LOWER(i.numeric_syllable) GLOB '*ui[1-5]' OR LOWER(i.numeric_syllable) GLOB '*un[1-5]' THEN 'general_standard_restored_final'
                            ELSE 'default_first_char'
                        END AS tone_matched_rule,
                        CASE
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN i.marked_syllable
                            WHEN SUBSTR(i.marked_syllable, 1, 1) IN ('a','o','e','ê','ā','ō','ē','ế','à','ò','è','ǎ','ǒ','ě','á','ó','é') THEN i.marked_syllable
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 2)) IN ('zh','ch','sh') AND LENGTH(i.marked_syllable) > 2 AND SUBSTR(i.marked_syllable, 3, 1) IN ('i','ī','í','ǐ','ì') THEN '_' || SUBSTR(i.marked_syllable, 3)
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 2)) IN ('zh','ch','sh') AND NOT (LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'ui[1-5]' OR LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'un[1-5]') THEN SUBSTR(i.marked_syllable, 3)
                            WHEN SUBSTR(LOWER(i.marked_syllable), 1, 1) IN ('z','c','s','r') AND LENGTH(i.marked_syllable) > 1 AND SUBSTR(i.marked_syllable, 2, 1) IN ('i','ī','í','ǐ','ì') THEN '_' || SUBSTR(i.marked_syllable, 2)
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 1)) IN ('j','q','x') AND SUBSTR(i.marked_syllable, 2, 1) IN ('u','ū','ú','ǔ','ù','ü','ǖ','ǘ','ǚ','ǜ') THEN CASE WHEN SUBSTR(i.marked_syllable, 2, 1) = 'u' THEN 'ü' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ū' THEN 'ǖ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ú' THEN 'ǘ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ǔ' THEN 'ǚ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ù' THEN 'ǜ' || SUBSTR(i.marked_syllable, 3) ELSE SUBSTR(i.marked_syllable, 2) END
                            WHEN LENGTH(i.marked_syllable) >= 2 AND LOWER(SUBSTR(i.marked_syllable, 1, 1)) = 'y' AND SUBSTR(i.marked_syllable, 2, 1) IN ('u','ū','ú','ǔ','ù','ü','ǖ','ǘ','ǚ','ǜ') THEN CASE WHEN SUBSTR(i.marked_syllable, 2, 1) = 'u' THEN 'ü' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ū' THEN 'ǖ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ú' THEN 'ǘ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ǔ' THEN 'ǚ' || SUBSTR(i.marked_syllable, 3) WHEN SUBSTR(i.marked_syllable, 2, 1) = 'ù' THEN 'ǜ' || SUBSTR(i.marked_syllable, 3) ELSE SUBSTR(i.marked_syllable, 2) END
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'i' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'you1' THEN 'iōu'
                            WHEN LOWER(i.numeric_syllable) GLOB 'you2' THEN 'ióu'
                            WHEN LOWER(i.numeric_syllable) GLOB 'you3' THEN 'iǒu'
                            WHEN LOWER(i.numeric_syllable) GLOB 'you4' THEN 'iòu'
                            WHEN LOWER(i.numeric_syllable) GLOB 'you5' THEN 'iou'
                            WHEN LOWER(i.numeric_syllable) GLOB 'ya*' THEN 'i' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'ye*' THEN 'i' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'yo*' AND LOWER(i.numeric_syllable) NOT GLOB 'yong*' AND LOWER(i.numeric_syllable) NOT GLOB 'you*' THEN 'i' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei1' THEN 'uēi'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei2' THEN 'uéi'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei3' THEN 'uěi'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei4' THEN 'uèi'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wei5' THEN 'uei'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen1' THEN 'uēn'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen2' THEN 'uén'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen3' THEN 'uěn'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen4' THEN 'uèn'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wen5' THEN 'uen'
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng1' THEN 'uēng'
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng2' THEN 'uéng'
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng3' THEN 'uěng'
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng4' THEN 'uèng'
                            WHEN LOWER(i.numeric_syllable) GLOB 'weng5' THEN 'ueng'
                            WHEN LOWER(i.numeric_syllable) GLOB 'wai*' THEN 'u' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wan*' THEN 'u' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wang*' THEN 'u' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wa*' THEN 'u' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB 'wo*' AND LOWER(i.numeric_syllable) NOT GLOB 'wong*' THEN 'u' || SUBSTR(i.marked_syllable, 2)
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu1' AND LOWER(i.numeric_syllable) NOT GLOB 'you1' THEN 'iōu'
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu2' AND LOWER(i.numeric_syllable) NOT GLOB 'you2' THEN 'ióu'
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu3' AND LOWER(i.numeric_syllable) NOT GLOB 'you3' THEN 'iǒu'
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu4' AND LOWER(i.numeric_syllable) NOT GLOB 'you4' THEN 'iòu'
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu5' AND LOWER(i.numeric_syllable) NOT GLOB 'you5' THEN 'iou'
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui1' THEN 'uēi'
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui2' THEN 'uéi'
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui3' THEN 'uěi'
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui4' THEN 'uèi'
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui5' THEN 'uei'
                            WHEN LOWER(i.numeric_syllable) GLOB '*un1' THEN 'uēn'
                            WHEN LOWER(i.numeric_syllable) GLOB '*un2' THEN 'uén'
                            WHEN LOWER(i.numeric_syllable) GLOB '*un3' THEN 'uěn'
                            WHEN LOWER(i.numeric_syllable) GLOB '*un4' THEN 'uèn'
                            WHEN LOWER(i.numeric_syllable) GLOB '*un5' THEN 'uen'
                            ELSE CASE WHEN LENGTH(i.marked_syllable) > 1 THEN SUBSTR(i.marked_syllable, 2) ELSE '' END
                        END AS current_rule_tone_final
                    FROM inventory i
                )
                SELECT
                    ns.numeric_syllable AS original_numeric_syllable,
                    ns.marked_syllable AS original_marked_syllable,
                    su.source_tables,
                    su.flattened_row_count,
                    su.has_single_char,
                    su.has_phrase,
                    su.single_char_distinct_count,
                    su.phrase_distinct_count,
                    ns.expected_initial_hint,
                    ns.numeric_matched_rule,
                    ts.tone_matched_rule,
                    ns.current_rule_initial,
                    ns.current_rule_numeric_final,
                    ts.current_rule_tone_final,
                    CASE
                        WHEN SUBSTR(ns.current_rule_numeric_final, -1) BETWEEN '1' AND '5'
                        THEN SUBSTR(
                            ns.current_rule_numeric_final,
                            1,
                            LENGTH(ns.current_rule_numeric_final) - 1
                        )
                        ELSE ns.current_rule_numeric_final
                    END AS current_rule_final_base,
                    CASE
                        WHEN SUBSTR(ns.current_rule_numeric_final, -1) BETWEEN '1' AND '5'
                        THEN CAST(SUBSTR(ns.current_rule_numeric_final, -1) AS INTEGER)
                        ELSE NULL
                    END AS current_rule_tone_number,
                    ns.current_rule_initial || ' / ' || ns.current_rule_numeric_final AS current_rule_numeric_split,
                    ns.current_rule_initial || ' / ' || ts.current_rule_tone_final AS current_rule_tone_split,
                    ns.current_rule_initial || ' / ' || ts.current_rule_tone_final AS marked_rule_split,
                    CASE WHEN ns.expected_initial_hint = ns.current_rule_initial THEN 1 ELSE 0 END AS initial_matches_hint
                FROM numeric_split ns
                JOIN tone_split ts
                    ON ts.numeric_syllable = ns.numeric_syllable
                 AND ts.marked_syllable = ns.marked_syllable
                LEFT JOIN source_usage su
                    ON su.numeric_syllable = ns.numeric_syllable
                 AND su.marked_syllable = ns.marked_syllable;

                CREATE VIEW v_syllable_split_audit AS
                WITH current_rule AS (
                    SELECT
                        original_numeric_syllable AS numeric_syllable,
                        original_marked_syllable AS marked_syllable,
                        source_tables,
                        flattened_row_count,
                        has_single_char,
                        has_phrase,
                        single_char_distinct_count,
                        phrase_distinct_count,
                        expected_initial_hint,
                        current_rule_initial,
                        current_rule_numeric_final,
                        current_rule_tone_final,
                        current_rule_final_base,
                        current_rule_tone_number,
                        current_rule_numeric_split,
                        current_rule_tone_split,
                        marked_rule_split,
                        numeric_matched_rule,
                        tone_matched_rule,
                        CASE WHEN SUBSTR(original_numeric_syllable, -1) BETWEEN '1' AND '5' THEN SUBSTR(original_numeric_syllable, 1, LENGTH(original_numeric_syllable) - 1) ELSE original_numeric_syllable END AS base_syllable
                    FROM v_syllable_split_current_rule
                )
                SELECT
                    numeric_syllable,
                    marked_syllable,
                    base_syllable,
                    source_tables,
                    flattened_row_count,
                    has_single_char,
                    has_phrase,
                    single_char_distinct_count,
                    phrase_distinct_count,
                    expected_initial_hint,
                    current_rule_initial,
                    current_rule_numeric_final,
                    current_rule_tone_final,
                    current_rule_final_base,
                    current_rule_tone_number,
                    current_rule_numeric_split,
                    current_rule_tone_split,
                    marked_rule_split,
                    numeric_matched_rule,
                    tone_matched_rule,
                    CASE
                        WHEN base_syllable IN ('ê', 'm', 'n', 'ng') THEN 'special_standalone'
                        WHEN base_syllable GLOB '[aeo]*' OR base_syllable GLOB 'ê*' THEN 'zero_initial'
                        WHEN base_syllable IN ('zhi', 'chi', 'shi', 'ri', 'zi', 'ci', 'si') THEN 'tongue_tip_i'
                        WHEN (base_syllable GLOB 'zh*' OR base_syllable GLOB 'ch*' OR base_syllable GLOB 'sh*') AND NOT (base_syllable GLOB 'zhui' OR base_syllable GLOB 'zhun' OR base_syllable GLOB 'chui' OR base_syllable GLOB 'chun' OR base_syllable GLOB 'shui' OR base_syllable GLOB 'shun') THEN 'zh_ch_sh'
                        WHEN base_syllable GLOB '[jqx]u*' THEN 'u_to_umlaut_candidate'
                        WHEN base_syllable GLOB 'yu*' THEN 'yu_umlaut_placeholder'
                        WHEN base_syllable GLOB 'yong*' THEN 'yong_cuokou_placeholder'
                        WHEN base_syllable GLOB 'ya*' OR base_syllable GLOB 'ye*' OR base_syllable GLOB 'you*' OR base_syllable = 'yo' THEN 'y_standard_final_restored'
                        WHEN base_syllable GLOB 'wei*' OR base_syllable GLOB 'wen*' OR base_syllable GLOB 'weng*' OR base_syllable GLOB 'wai*' OR base_syllable GLOB 'wan*' OR base_syllable GLOB 'wang*' OR base_syllable GLOB 'wa*' OR (base_syllable GLOB 'wo*' AND base_syllable NOT GLOB 'wong*') THEN 'w_standard_final_restored'
                        WHEN (base_syllable GLOB '*iu' AND base_syllable NOT GLOB 'you') OR base_syllable GLOB '*ui' OR base_syllable GLOB '*un' THEN 'general_standard_final_restored'
                        WHEN base_syllable GLOB 'w*' OR (base_syllable GLOB 'y*' AND NOT base_syllable GLOB 'yu*') THEN 'semivowel_initial'
                        WHEN INSTR(base_syllable, 'ü') > 0 THEN 'contains_umlaut'
                        ELSE 'regular'
                    END AS audit_category,
                    CASE
                        WHEN base_syllable IN ('ê', 'm', 'n', 'ng') THEN 'special standalone syllable handled as zero-initial special case'
                        WHEN base_syllable GLOB '[aeo]*' OR base_syllable GLOB 'ê*' THEN 'starts with vowel-like letter; likely zero initial'
                        WHEN base_syllable IN ('zhi', 'chi', 'shi', 'ri', 'zi', 'ci', 'si') THEN 'tongue-tip i syllable; splitter uses underscored numeric final'
                        WHEN base_syllable GLOB '[jqx]u*' THEN 'j/q/x before u-family currently reconstruct to ü-family finals'
                        WHEN base_syllable GLOB 'yu*' THEN 'current splitter treats yu-family as ɥ + ü-family final'
                        WHEN base_syllable GLOB 'yong*' THEN 'current splitter treats yong-family as ɥ + iong-family final while keeping the standard pinyin final form'
                        WHEN base_syllable GLOB 'ya*' OR base_syllable GLOB 'ye*' OR base_syllable GLOB 'you*' OR base_syllable = 'yo' THEN 'current splitter restores standard i-family finals for non-umlaut y spellings'
                        WHEN base_syllable GLOB 'wei*' OR base_syllable GLOB 'wen*' OR base_syllable GLOB 'weng*' OR base_syllable GLOB 'wai*' OR base_syllable GLOB 'wan*' OR base_syllable GLOB 'wang*' OR base_syllable GLOB 'wa*' OR (base_syllable GLOB 'wo*' AND base_syllable NOT GLOB 'wong*') THEN 'current splitter restores standard u-family finals for non-wu w spellings'
                        WHEN base_syllable GLOB 'wong*' THEN 'wong 源语料形式当前保留为 w + ong；不预设 uong，后续如需合码只在编码投影层处理'
                        WHEN (base_syllable GLOB '*iu' AND base_syllable NOT GLOB 'you') OR base_syllable GLOB '*ui' OR base_syllable GLOB '*un' THEN 'current splitter restores scheme-standard iou/uei/uen finals for generic abbreviated spellings'
                        WHEN base_syllable GLOB 'w*' OR (base_syllable GLOB 'y*' AND NOT base_syllable GLOB 'yu*') THEN 'semivowel-led spelling; current splitter preserves w/y except the explicit restored families'
                        WHEN INSTR(base_syllable, 'ü') > 0 THEN 'contains explicit ü in source syllable'
                        ELSE 'regular split path'
                    END AS audit_note
                FROM current_rule;

                CREATE VIEW v_syllable_splitter_current_rule AS
                WITH inventory AS (
                    SELECT
                        numeric_syllable,
                        marked_syllable,
                        CASE
                            WHEN SUBSTR(numeric_syllable, -1) BETWEEN '1' AND '5' THEN SUBSTR(numeric_syllable, 1, LENGTH(numeric_syllable) - 1)
                            ELSE numeric_syllable
                        END AS base_syllable
                    FROM {quoted_table}
                ),
                source_usage AS (
                    SELECT
                        numeric_syllable,
                        marked_syllable,
                        source_tables,
                        flattened_distinct_count AS flattened_row_count,
                        has_single_char,
                        has_phrase,
                        single_char_distinct_count,
                        phrase_distinct_count
                    FROM {quoted_table}
                ),
                rule_eval AS (
                    SELECT
                        i.numeric_syllable,
                        i.marked_syllable,
                        i.base_syllable,
                        su.source_tables,
                        su.flattened_row_count,
                        su.has_single_char,
                        su.has_phrase,
                        su.single_char_distinct_count,
                        su.phrase_distinct_count,
                        CASE
                            WHEN i.base_syllable IN ('ê', 'm', 'n', 'ng') THEN 'special_standalone'
                            WHEN i.base_syllable GLOB '[aeo]*' OR i.base_syllable GLOB 'ê*' THEN 'zero_initial'
                            WHEN i.base_syllable IN ('zhi', 'chi', 'shi', 'ri', 'zi', 'ci', 'si') THEN 'tongue_tip_i'
                            WHEN (i.base_syllable GLOB 'zh*' OR i.base_syllable GLOB 'ch*' OR i.base_syllable GLOB 'sh*') AND NOT (i.base_syllable GLOB 'zhui' OR i.base_syllable GLOB 'zhun' OR i.base_syllable GLOB 'chui' OR i.base_syllable GLOB 'chun' OR i.base_syllable GLOB 'shui' OR i.base_syllable GLOB 'shun') THEN 'zh_ch_sh'
                            WHEN i.base_syllable GLOB '[jqxy]u*' OR i.base_syllable GLOB 'yu*' THEN 'u_to_umlaut_candidate'
                            WHEN i.base_syllable GLOB 'yong*' THEN 'yong_cuokou_placeholder'
                            WHEN (i.base_syllable GLOB '*iu' AND i.base_syllable NOT GLOB 'you') OR i.base_syllable GLOB '*ui' OR i.base_syllable GLOB '*un' THEN 'general_standard_final_restored'
                            WHEN i.base_syllable GLOB 'w*' OR i.base_syllable GLOB 'y*' THEN 'semivowel_initial'
                            WHEN INSTR(i.base_syllable, 'ü') > 0 THEN 'contains_umlaut'
                            ELSE 'regular'
                        END AS audit_category,
                        CASE
                            WHEN i.base_syllable IN ('ê', 'm', 'n', 'ng') THEN ''''
                            WHEN i.base_syllable GLOB '[aeo]*' OR i.base_syllable GLOB 'ê*' THEN ''''
                            WHEN i.base_syllable GLOB 'yong*' THEN 'ɥ'
                            WHEN i.base_syllable IN ('zhi', 'chi', 'shi') THEN SUBSTR(i.base_syllable, 1, 2)
                            WHEN i.base_syllable IN ('ri', 'zi', 'ci', 'si') THEN SUBSTR(i.base_syllable, 1, 1)
                            WHEN i.base_syllable GLOB 'zh*' OR i.base_syllable GLOB 'ch*' OR i.base_syllable GLOB 'sh*' THEN SUBSTR(i.base_syllable, 1, 2)
                            ELSE SUBSTR(i.base_syllable, 1, 1)
                        END AS expected_initial_hint,
                        CASE
                            WHEN i.numeric_syllable = '' THEN ''
                            WHEN i.numeric_syllable IN ('ê1','ê2','ê3','ê4','ê5','m1','m2','m3','m4','m5','n1','n2','n3','n4','n5','ng1','ng2','ng3','ng4','ng5') THEN ''''
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e','ê','ā','ō','ē','ế','à','ò','è','ǎ','ǒ','ě','á','ó','é') THEN ''''
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') THEN LOWER(SUBSTR(i.numeric_syllable, 1, 2))
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('z','c','s','r') AND LENGTH(i.numeric_syllable) > 1 AND SUBSTR(i.numeric_syllable, 2, 1) = 'i' THEN SUBSTR(i.numeric_syllable, 1, 1)
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) IN ('j','q','x','y') AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN SUBSTR(i.numeric_syllable, 1, 1)
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'ɥ'
                            ELSE SUBSTR(i.numeric_syllable, 1, 1)
                        END AS numeric_split_initial,
                        CASE
                            WHEN i.numeric_syllable = '' THEN ''
                            WHEN i.numeric_syllable = 'ê1' THEN 'ê̄'
                            WHEN i.numeric_syllable = 'ê2' THEN 'ế'
                            WHEN i.numeric_syllable = 'ê3' THEN 'ê̌'
                            WHEN i.numeric_syllable = 'ê4' THEN 'ề'
                            WHEN i.numeric_syllable = 'ê5' THEN 'ê'
                            WHEN i.numeric_syllable = 'm1' THEN 'm̄'
                            WHEN i.numeric_syllable = 'm2' THEN 'ḿ'
                            WHEN i.numeric_syllable = 'm3' THEN 'm̌'
                            WHEN i.numeric_syllable = 'm4' THEN 'm̀'
                            WHEN i.numeric_syllable = 'm5' THEN 'm'
                            WHEN i.numeric_syllable = 'n1' THEN 'n̄'
                            WHEN i.numeric_syllable = 'n2' THEN 'ń'
                            WHEN i.numeric_syllable = 'n3' THEN 'ň'
                            WHEN i.numeric_syllable = 'n4' THEN 'ǹ'
                            WHEN i.numeric_syllable = 'n5' THEN 'n'
                            WHEN i.numeric_syllable = 'ng1' THEN 'n̄g'
                            WHEN i.numeric_syllable = 'ng2' THEN 'ńg'
                            WHEN i.numeric_syllable = 'ng3' THEN 'ňg'
                            WHEN i.numeric_syllable = 'ng4' THEN 'ǹg'
                            WHEN i.numeric_syllable = 'ng5' THEN 'ng'
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('a','o','e','ê','ā','ō','ē','ế','à','ò','è','ǎ','ǒ','ě','á','ó','é') THEN i.numeric_syllable
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 2)) IN ('zh','ch','sh') AND NOT (LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'ui[1-5]' OR LOWER(SUBSTR(i.numeric_syllable, 3)) GLOB 'un[1-5]') THEN CASE WHEN LENGTH(i.numeric_syllable) > 2 AND SUBSTR(i.numeric_syllable, 3, 1) = 'i' THEN '_' || SUBSTR(i.numeric_syllable, 3) ELSE SUBSTR(i.numeric_syllable, 3) END
                            WHEN SUBSTR(i.numeric_syllable, 1, 1) IN ('z','c','s','r') AND LENGTH(i.numeric_syllable) > 1 AND SUBSTR(i.numeric_syllable, 2, 1) = 'i' THEN '_' || SUBSTR(i.numeric_syllable, 2)
                            WHEN LENGTH(i.numeric_syllable) >= 2 AND LOWER(SUBSTR(i.numeric_syllable, 1, 1)) IN ('j','q','x','y') AND LOWER(SUBSTR(i.numeric_syllable, 2, 1)) = 'u' THEN CASE WHEN LENGTH(i.numeric_syllable) > 2 THEN 'ü' || SUBSTR(i.numeric_syllable, 3) ELSE 'ü' END
                            WHEN LOWER(i.numeric_syllable) GLOB 'yong*' THEN 'iong' || SUBSTR(i.numeric_syllable, 5)
                            WHEN LOWER(i.numeric_syllable) GLOB '*iu[1-5]' AND LOWER(i.numeric_syllable) NOT GLOB 'you*' THEN 'iou' || SUBSTR(i.numeric_syllable, -1)
                            WHEN LOWER(i.numeric_syllable) GLOB '*ui[1-5]' THEN 'uei' || SUBSTR(i.numeric_syllable, -1)
                            WHEN LOWER(i.numeric_syllable) GLOB '*un[1-5]' THEN 'uen' || SUBSTR(i.numeric_syllable, -1)
                            ELSE CASE WHEN LENGTH(i.numeric_syllable) > 1 THEN SUBSTR(i.numeric_syllable, 2) ELSE '' END
                        END AS numeric_split_final
                    FROM inventory i
                    LEFT JOIN source_usage su
                        ON su.numeric_syllable = i.numeric_syllable
                     AND su.marked_syllable = i.marked_syllable
                )
                SELECT * FROM rule_eval;
                """
        )


def main() -> None:
    args = parse_args()
    db_path = args.db_path.resolve()

    with sqlite3.connect(db_path, timeout=30.0) as connection:
        connection.execute("PRAGMA busy_timeout = 30000")
        if args.views_only:
            row_count = connection.execute(
                f"SELECT COUNT(*) FROM {quote_identifier(args.table_name)}"
            ).fetchone()[0]
        else:
            row_count = refresh_materialized_table(connection, args.table_name)
        rebuild_analysis_views(connection, args.table_name)
        connection.commit()

    print(f"refreshed {args.table_name} in {db_path}")
    print(f"rows={row_count}")


if __name__ == "__main__":
    main()
