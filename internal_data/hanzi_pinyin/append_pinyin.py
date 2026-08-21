#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Load pinyin_source_staging rows into hanzi_pinyin (sparse table, direct copy).",
    )
    parser.add_argument(
        "--db",
        default=str(Path(__file__).resolve().with_name("hanzi_pinyin.db")),
        help="Target hanzi_pinyin.db path",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write back changes, only report counts",
    )
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    staging_count = cur.execute("SELECT COUNT(*) FROM pinyin_source_staging").fetchone()[0]
    if staging_count == 0:
        print("pinyin_source_staging table is empty; import data first with pinyin_source_staging.py")
        conn.close()
        return 1

    if not args.dry_run:
        cur.execute("DELETE FROM hanzi_pinyin")
        cur.execute("""
            INSERT INTO hanzi_pinyin (
                codepoint, hanzi, common_reading, readings, common_reading_source, is_single
            )
            SELECT
                codepoint, hanzi, common_reading, readings, common_reading_source, is_single
            FROM pinyin_source_staging
        """)
        conn.commit()

    print(f"loaded {staging_count:,} rows from pinyin_source_staging -> hanzi_pinyin")
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
