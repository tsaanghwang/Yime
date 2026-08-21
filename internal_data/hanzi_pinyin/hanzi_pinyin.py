import sqlite3
import sys
from pathlib import Path

from hanzi_pinyin_source_io import HANZI_PINYIN_DDL

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")


def build_hanzi_pinyin():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS hanzi_pinyin")
    cur.execute(HANZI_PINYIN_DDL)

    conn.commit()

    hanzi_count = cur.execute("SELECT COUNT(*) FROM hanzi").fetchone()[0]

    conn.close()

    print(f"hanzi_pinyin 表已创建（空表，仅存有拼音汉字；hanzi 主表 {hanzi_count:,} 条）")
    print(f"数据库: {DB_FILE}")


def console_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode(sys.stdout.encoding or "utf-8", errors="backslashreplace"))


def create_views():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    console_print("\n── 创建 hanzi_pinyin 视图 ──")

    cur.execute("CREATE INDEX IF NOT EXISTS idx_hanzi_hanzi ON hanzi(hanzi)")

    cur.execute("DROP VIEW IF EXISTS view_pinyin_inspection")
    cur.execute("DROP VIEW IF EXISTS view_pinyin_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_pinyin_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_pinyin_with_multireadings")
    cur.execute("DROP VIEW IF EXISTS view_pinyin_single_reading_not_toned")
    cur.execute("DROP VIEW IF EXISTS view_pinyin_staging_diff")

    cur.execute("""
        CREATE VIEW view_pinyin_inspection AS
        SELECT
            h.codepoint,
            h.hanzi,
            h.block,
            h.block_order,
            hf.frequency,
            hr.common_reading AS pinyin,
            hr.readings AS pinyin_candidates,
            hr.common_reading_source,
            hr.is_single,
            CASE
                WHEN hr.readings IS NULL OR hr.readings = '' THEN 0
                ELSE LENGTH(hr.readings) - LENGTH(REPLACE(hr.readings, ',', '')) + 1
            END AS candidate_count,
            CASE
                WHEN TRIM(COALESCE(hr.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN hr.is_single = 1 THEN 0
                WHEN hr.readings IS NOT NULL AND hr.readings <> '' THEN 1
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
        LEFT JOIN hanzi_pinyin hr ON h.codepoint = hr.codepoint
        LEFT JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_with_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM hanzi_pinyin
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_without_pinyin AS
        SELECT
            h.codepoint,
            h.hanzi,
            NULL AS common_reading,
            NULL AS readings,
            NULL AS common_reading_source,
            NULL AS is_single
        FROM hanzi h
        LEFT JOIN hanzi_pinyin hr ON h.codepoint = hr.codepoint
        WHERE hr.codepoint IS NULL
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_with_multireadings AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM hanzi_pinyin
        WHERE is_single = 0
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_single_reading_not_toned AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM hanzi_pinyin
        WHERE is_single = 1
          AND common_reading NOT GLOB '*[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]*'
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_staging_diff AS
        SELECT
            ps.codepoint,
            ps.hanzi,
            hp.common_reading AS pinyin_reading,
            hp.readings AS pinyin_candidates,
            hp.common_reading_source AS pinyin_source,
            hp.is_single AS pinyin_is_single,
            ps.common_reading AS staging_reading,
            ps.readings AS staging_candidates,
            ps.common_reading_source AS staging_source,
            ps.is_single AS staging_is_single,
            CASE
                WHEN hp.codepoint IS NULL THEN 'only_in_staging'
                WHEN hp.readings = ps.readings
                     AND COALESCE(hp.common_reading, '') = COALESCE(ps.common_reading, '')
                     AND hp.is_single = ps.is_single
                THEN 'same'
                ELSE 'different'
            END AS diff_type
        FROM pinyin_source_staging ps
        LEFT JOIN hanzi_pinyin hp ON ps.codepoint = hp.codepoint
        WHERE hp.codepoint IS NULL
           OR hp.readings <> ps.readings
           OR COALESCE(hp.common_reading, '') <> COALESCE(ps.common_reading, '')
           OR hp.is_single <> ps.is_single
        UNION ALL
        SELECT
            hp.codepoint,
            hp.hanzi,
            hp.common_reading,
            hp.readings,
            hp.common_reading_source,
            hp.is_single,
            ps.common_reading,
            ps.readings,
            ps.common_reading_source,
            ps.is_single,
            'only_in_pinyin' AS diff_type
        FROM hanzi_pinyin hp
        LEFT JOIN pinyin_source_staging ps ON hp.codepoint = ps.codepoint
        WHERE ps.codepoint IS NULL
    """)

    conn.commit()

    cur.execute(
        "SELECT hanzi, pinyin, candidate_count, is_polyphonic, frequency_band "
        "FROM view_pinyin_inspection WHERE has_pinyin = 1 "
        "ORDER BY block_order ASC, codepoint ASC LIMIT 5"
    )
    console_print(f"view_pinyin_inspection 有拼音前5个: {cur.fetchall()}")

    pinyin_count = cur.execute("SELECT COUNT(*) FROM hanzi_pinyin").fetchone()[0]
    without_count = cur.execute("SELECT COUNT(*) FROM view_pinyin_without_pinyin").fetchone()[0]
    console_print(f"hanzi_pinyin: {pinyin_count:,} 条；view_pinyin_without_pinyin: {without_count:,} 条")

    conn.close()


if __name__ == "__main__":
    build_hanzi_pinyin()
    create_views()
