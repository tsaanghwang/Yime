import sqlite3
from pathlib import Path

from pinyin_match import MANDARIN_SOURCE_COLUMNS

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "unihan_readings.db"

# 已下线管线遗留对象；fresh build 不会创建，DROP IF EXISTS 便于升级旧库
_LEGACY_VIEWS = (
    "view_readings_diff_summary",
    "view_readings_diff_exact",
    "view_readings_diff_order_only",
    "view_readings_diff_content",
    "view_readings_diff_content_superset",
    "view_readings_diff_content_other",
    "view_readings_diff_only_unihan",
    "view_readings_diff_only_hanzi_pinyin",
    "view_tghz2013_inspection",
    "view_tghz2013_with_pinyin",
    "view_tghz2013_without_pinyin",
    "view_tghz2013_polyphonic",
)

_LEGACY_TABLES = (
    "readings_diff",
    "hanzi_pinyin_readings_ref",
    "mandarin_readings_mode_diff",
    "readings_mode_hanzi_pinyin_diff",
    "tghz2013_pinyin",
)


def drop_legacy_artifacts(cur: sqlite3.Cursor) -> None:
    for view_name in _LEGACY_VIEWS:
        cur.execute(f"DROP VIEW IF EXISTS {view_name}")
    for table_name in _LEGACY_TABLES:
        cur.execute(f"DROP TABLE IF EXISTS {table_name}")


def recreate_clean_views() -> None:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    drop_legacy_artifacts(cur)

    for col in MANDARIN_SOURCE_COLUMNS:
        view_name = f"view_{col[1:]}" if col.startswith("k") else f"view_{col}"
        cur.execute(f"DROP VIEW IF EXISTS {view_name}")
        cur.execute(f"""
            CREATE VIEW {view_name} AS
            SELECT h.codepoint, h.hanzi, u.{col} AS reading
            FROM hanzi h
            INNER JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
            WHERE u.{col} IS NOT NULL AND u.{col} != ''
            ORDER BY h.block_order, h.codepoint
        """)

    cur.execute("DROP VIEW IF EXISTS view_hanzi_frequency")
    cur.execute("""
        CREATE VIEW view_hanzi_frequency AS
        SELECT
            h.codepoint,
            h.hanzi,
            hf.frequency,
            hf.frequency_source
        FROM hanzi h
        INNER JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
    """)

    cur.execute("DROP VIEW IF EXISTS view_tghz2013_frequency")
    cur.execute("""
        CREATE VIEW view_tghz2013_frequency AS
        SELECT
            h.codepoint,
            h.hanzi,
            u.kTGHZ2013 AS reading,
            hf.frequency,
            hf.frequency_source
        FROM hanzi h
        INNER JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
        INNER JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
        WHERE u.kTGHZ2013 IS NOT NULL AND TRIM(u.kTGHZ2013) <> ''
    """)

    for view_name in (
        "view_mandarin_merged_inspection",
        "view_mandarin_merged_with_pinyin",
        "view_mandarin_merged_without_pinyin",
        "view_mandarin_merged_polyphonic",
        "view_mandarin_readings_corrections_pending",
        "view_mandarin_readings_corrections_approved",
    ):
        cur.execute(f"DROP VIEW IF EXISTS {view_name}")

    cur.execute("""
        CREATE VIEW view_mandarin_merged_inspection AS
        SELECT
            h.codepoint,
            h.hanzi,
            h.block,
            h.block_order,
            hf.frequency,
            mm.common_reading,
            mm.readings,
            mm.common_reading_source,
            mm.is_single,
            CASE
                WHEN mm.readings IS NULL OR mm.readings = '' THEN 0
                ELSE LENGTH(mm.readings) - LENGTH(REPLACE(mm.readings, ',', '')) + 1
            END AS candidate_count,
            CASE
                WHEN TRIM(COALESCE(mm.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN mm.is_single = 1 THEN 0
                WHEN mm.readings IS NOT NULL AND mm.readings <> '' THEN 1
                ELSE 0
            END AS is_polyphonic,
            CASE
                WHEN hf.frequency >= 1000000 THEN 'very_high'
                WHEN hf.frequency >= 100000 THEN 'high'
                WHEN hf.frequency >= 10000 THEN 'medium'
                WHEN hf.frequency >= 1 THEN 'low'
                ELSE 'zero'
            END AS frequency_band
        FROM hanzi h
        LEFT JOIN mandarin_readings_merged mm ON h.codepoint = mm.codepoint
        LEFT JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
    """)

    cur.execute("""
        CREATE VIEW view_mandarin_merged_with_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM mandarin_readings_merged
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_mandarin_merged_without_pinyin AS
        SELECT h.codepoint, h.hanzi
        FROM hanzi h
        LEFT JOIN mandarin_readings_merged mm ON h.codepoint = mm.codepoint
        WHERE mm.codepoint IS NULL
           OR COALESCE(mm.common_reading, '') = ''
    """)

    cur.execute("""
        CREATE VIEW view_mandarin_merged_polyphonic AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM mandarin_readings_merged
        WHERE is_single = 0
          AND COALESCE(common_reading, '') <> ''
    """)

    from mandarin_readings_corrections_io import create_correction_views

    create_correction_views(cur)

    conn.commit()
    conn.close()
    print(
        "视图已重建：Unihan 五列字段视图 + hanzi_frequency / tghz2013_frequency "
        "+ mandarin 合并视图 + corrections 视图"
    )

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('SELECT name FROM sqlite_master WHERE type="table"')
    print("当前表:", [row[0] for row in cur.fetchall()])
    cur.execute('SELECT name FROM sqlite_master WHERE type="view"')
    print("当前视图:", [row[0] for row in cur.fetchall()])
    conn.close()


if __name__ == "__main__":
    recreate_clean_views()
