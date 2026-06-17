#!/usr/bin/env python3
"""Populate hanzi master table in unihan_readings.db."""

import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
HANZI_PINYIN_DIR = SCRIPT_DIR.parents[1] / "internal_data" / "hanzi_pinyin"
sys.path.insert(0, str(HANZI_PINYIN_DIR))

from hanzi_catalog import create_hanzi_table, hanzi_count, populate_hanzi  # noqa: E402

DB_PATH = SCRIPT_DIR / "unihan_readings.db"


def drop_unihan_reading_objects(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    for (name,) in cur.execute(
        "SELECT name FROM sqlite_master WHERE type = 'view'"
    ).fetchall():
        cur.execute(f"DROP VIEW IF EXISTS {name}")
    cur.execute("DROP TABLE IF EXISTS unihan_readings_clean")
    cur.execute("DROP TABLE IF EXISTS unihan_readings_raw")
    cur.execute("DROP TABLE IF EXISTS mandarin_readings_merged")
    cur.execute("DROP TABLE IF EXISTS readings_diff")
    cur.execute("DROP TABLE IF EXISTS hanzi_pinyin_readings_ref")
    cur.execute("DROP TABLE IF EXISTS hanzi_frequency")
    conn.commit()


def main() -> int:
    rebuild = "--rebuild" in sys.argv
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")

    if not rebuild and hanzi_count(conn) > 0:
        count = hanzi_count(conn)
        print(f"hanzi 表已存在: {count:,} 条，跳过（使用 --rebuild 强制重建）")
        conn.close()
        return 0

    if rebuild:
        drop_unihan_reading_objects(conn)

    def on_block(block_name: str, count: int) -> None:
        print(f"{block_name}: {count:,} 个")

    create_hanzi_table(conn, drop_existing=True)
    total = populate_hanzi(conn, on_block=on_block)
    conn.close()
    print(f"\n合计: {total:,} 个汉字")
    print(f"数据库: {DB_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
