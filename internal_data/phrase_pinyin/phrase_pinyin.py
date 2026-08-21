import sqlite3
import sys
from pathlib import Path

DB_FILE = str(Path(__file__).parent / "phrase_pinyin.db")


def build_phrase_pinyin():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS phrase_pinyin")

    cur.execute("""
        CREATE TABLE phrase_pinyin (
            phrase          TEXT PRIMARY KEY,
            phrase_len      INTEGER NOT NULL,
            common_reading  TEXT,
            readings        TEXT
        )
    """)

    conn.commit()

    count = cur.execute("SELECT COUNT(*) FROM phrase_pinyin").fetchone()[0]

    conn.close()

    print(f"phrase_pinyin 表已创建，共 {count:,} 条记录")
    print(f"数据库: {DB_FILE}")


def console_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode(sys.stdout.encoding or "utf-8", errors="backslashreplace"))


def create_views():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    console_print("\n── 创建 phrase_pinyin 视图 ──")

    cur.execute("DROP VIEW IF EXISTS view_phrase_inspection")
    cur.execute("DROP VIEW IF EXISTS view_phrase_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_phrase_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_phrase_staging_diff")

    cur.execute("""
        CREATE VIEW view_phrase_inspection AS
        SELECT
            pp.phrase,
            pp.phrase_len,
            pp.common_reading AS pinyin,
            pp.readings AS pinyin_candidates,
            CASE
                WHEN pp.readings IS NULL OR pp.readings = '' THEN 0
                ELSE LENGTH(pp.readings) - LENGTH(REPLACE(pp.readings, '|', '')) + 1
            END AS reading_count,
            CASE
                WHEN TRIM(COALESCE(pp.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN pp.readings IS NOT NULL
                     AND pp.readings <> ''
                     AND INSTR(pp.readings, '|') > 0 THEN 1
                ELSE 0
            END AS is_polyphonic
        FROM phrase_pinyin pp
    """)

    cur.execute("""
        CREATE VIEW view_phrase_with_pinyin AS
        SELECT phrase, phrase_len, common_reading, readings
        FROM phrase_pinyin
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_phrase_without_pinyin AS
        SELECT phrase, phrase_len, common_reading, readings
        FROM phrase_pinyin
        WHERE common_reading IS NULL OR common_reading = ''
    """)

    cur.execute("""
        CREATE VIEW view_phrase_staging_diff AS
        SELECT
            pp.phrase,
            pp.common_reading AS pinyin_reading,
            pp.readings AS pinyin_candidates,
            ps.common_reading AS staging_reading,
            ps.readings AS staging_candidates,
            CASE
                WHEN pp.readings = ps.readings THEN 'same'
                WHEN pp.readings IS NULL OR pp.readings = '' THEN 'only_in_staging'
                WHEN ps.readings IS NULL OR ps.readings = '' THEN 'only_in_pinyin'
                ELSE 'different'
            END AS diff_type
        FROM phrase_pinyin pp
        LEFT JOIN phrase_source_staging ps ON pp.phrase = ps.phrase
        WHERE pp.readings <> ps.readings
           OR (pp.readings IS NULL AND ps.readings IS NOT NULL)
           OR (pp.readings IS NOT NULL AND ps.readings IS NULL)
    """)

    conn.commit()

    cur.execute(
        "SELECT phrase, pinyin, reading_count, has_pinyin, is_polyphonic "
        "FROM view_phrase_inspection LIMIT 5"
    )
    console_print(f"view_phrase_inspection 前5个: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    build_phrase_pinyin()
    create_views()
