import sqlite3
import sys
from pathlib import Path

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")


def build_hanzi_pinyin():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS hanzi_pinyin")

    cur.execute("""
        CREATE TABLE hanzi_pinyin (
            codepoint       TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            hanzi           TEXT NOT NULL,
            common_reading  TEXT,
            readings        TEXT
        )
    """)

    cur.execute("""
        INSERT INTO hanzi_pinyin (codepoint, hanzi)
        SELECT codepoint, hanzi FROM hanzi
    """)

    conn.commit()

    count = cur.execute("SELECT COUNT(*) FROM hanzi_pinyin").fetchone()[0]

    conn.close()

    print(f"hanzi_pinyin 表已创建，共 {count:,} 条记录")
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
    cur.execute("DROP TABLE IF EXISTS hanzi_invalid_pinyin")

    cur.execute("""
        CREATE VIEW view_pinyin_inspection AS
        SELECT
            h.codepoint,
            h.hanzi,
            h.block,
            hf.frequency,
            hr.common_reading AS pinyin,
            hr.readings AS pinyin_candidates,
            CASE
                WHEN hr.readings IS NULL OR hr.readings = '' THEN 0
                ELSE LENGTH(hr.readings) - LENGTH(REPLACE(hr.readings, ',', '')) + 1
            END AS candidate_count,
            CASE
                WHEN TRIM(COALESCE(hr.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN hr.readings IS NOT NULL
                     AND hr.readings <> ''
                     AND LENGTH(hr.readings) - LENGTH(REPLACE(hr.readings, ',', '')) + 1 > 1 THEN 1
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
        SELECT codepoint, hanzi, common_reading, readings
        FROM hanzi_pinyin
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_without_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM hanzi_pinyin
        WHERE common_reading IS NULL OR common_reading = ''
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_with_multireadings AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM hanzi_pinyin
        WHERE COALESCE(common_reading, '') <> ''
          AND readings LIKE '%,%'
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_single_reading_not_toned AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM hanzi_pinyin
        WHERE COALESCE(common_reading, '') <> ''
          AND readings NOT LIKE '%,%'
           AND common_reading NOT GLOB '*[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]*'
    """)

    cur.execute("""
        CREATE VIEW view_pinyin_staging_diff AS
        SELECT
            h.codepoint,
            h.hanzi,
            hp.common_reading AS pinyin_reading,
            hp.readings AS pinyin_candidates,
            ps.common_reading AS staging_reading,
            ps.readings AS staging_candidates,
            CASE
                WHEN hp.readings = ps.readings THEN 'same'
                WHEN hp.readings IS NULL OR hp.readings = '' THEN 'only_in_staging'
                WHEN ps.readings IS NULL OR ps.readings = '' THEN 'only_in_pinyin'
                ELSE 'different'
            END AS diff_type
        FROM hanzi h
        LEFT JOIN hanzi_pinyin hp ON h.codepoint = hp.codepoint
        LEFT JOIN pinyin_source_staging ps ON h.codepoint = ps.codepoint
        WHERE hp.readings <> ps.readings
           OR (hp.readings IS NULL AND ps.readings IS NOT NULL)
           OR (hp.readings IS NOT NULL AND ps.readings IS NULL)
    """)

    conn.commit()

    cur.execute(
        "SELECT hanzi, pinyin, candidate_count, is_polyphonic, frequency_band "
        "FROM view_pinyin_inspection ORDER BY frequency DESC, codepoint ASC LIMIT 5"
    )
    console_print(f"view_pinyin_inspection 前5个: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    build_hanzi_pinyin()
    create_views()
