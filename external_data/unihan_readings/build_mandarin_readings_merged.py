#!/usr/bin/env python3
"""Build mandarin_readings_merged from cleaned Unihan Mandarin columns."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

from pinyin_match import MANDARIN_SOURCE_COLUMNS, merge_mandarin_readings
from mandarin_readings_supplement import apply_merged_supplements

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "unihan_readings.db"

MODE_ARTIFACTS = (
    "view_mandarin_readings_mode_diff",
    "view_readings_mode_hanzi_pinyin_summary",
    "view_readings_mode_with_smszd_better",
    "view_readings_mode_without_smszd_better",
    "view_readings_mode_hanzi_pinyin_same_quality",
)


def drop_mandarin_merge_mode_artifacts(cur: sqlite3.Cursor) -> None:
    for view_name in MODE_ARTIFACTS:
        cur.execute(f"DROP VIEW IF EXISTS {view_name}")
    cur.execute("DROP TABLE IF EXISTS mandarin_readings_mode_diff")
    cur.execute("DROP TABLE IF EXISTS readings_mode_hanzi_pinyin_diff")


def build_mandarin_readings_merged(cur: sqlite3.Cursor) -> tuple[int, dict[str, int], int]:
    source_columns = MANDARIN_SOURCE_COLUMNS
    source_filter = " OR ".join(
        f"(c.{col} IS NOT NULL AND TRIM(c.{col}) != '')"
        for col in source_columns
    )
    select_columns = ", ".join(f"c.{col}" for col in source_columns)
    rows = cur.execute(f"""
        SELECT
            h.codepoint,
            h.hanzi,
            {select_columns},
            r.kHanyuPinlu
        FROM hanzi h
        INNER JOIN unihan_readings_clean c ON h.codepoint = c.codepoint
        LEFT JOIN unihan_readings_raw r ON h.codepoint = r.codepoint
        WHERE {source_filter}
    """).fetchall()

    source_counts: dict[str, int] = {}
    single_count = 0
    insert_rows: list[tuple[str, str, str, str, str, int]] = []

    for row in rows:
        codepoint, hanzi, *field_values, raw_pinlu = row
        source_values = dict(zip(source_columns, field_values, strict=True))
        readings, common_reading, source, is_single = merge_mandarin_readings(
            source_values,
            raw_pinlu,
        )
        source_counts[source] = source_counts.get(source, 0) + 1
        if is_single:
            single_count += 1
        insert_rows.append(
            (
                codepoint,
                hanzi,
                readings,
                common_reading,
                source,
                1 if is_single else 0,
            )
        )

    drop_mandarin_merge_mode_artifacts(cur)
    cur.execute("DROP TABLE IF EXISTS mandarin_readings_merged")
    cur.execute("""
        CREATE TABLE mandarin_readings_merged (
            codepoint               TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            hanzi                   TEXT NOT NULL,
            readings                TEXT,
            common_reading          TEXT,
            common_reading_source   TEXT,
            is_single               INTEGER NOT NULL DEFAULT 0
        )
    """)
    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_mandarin_merged_common "
        "ON mandarin_readings_merged(common_reading)"
    )
    cur.executemany(
        "INSERT INTO mandarin_readings_merged "
        "(codepoint, hanzi, readings, common_reading, common_reading_source, is_single) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        insert_rows,
    )
    supplemented = apply_merged_supplements(cur)
    total = len(insert_rows) + len(supplemented)
    return total, source_counts, single_count, supplemented


def main() -> int:
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        cur = conn.cursor()
        for table in ("hanzi", "unihan_readings_clean", "unihan_readings_raw"):
            if cur.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                (table,),
            ).fetchone() is None:
                raise RuntimeError(f"{table} 不存在，请先完成 hanzi / Unihan 导入")

        total, source_counts, single_count, supplemented = build_mandarin_readings_merged(cur)
        conn.commit()

        try:
            sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        except (AttributeError, ValueError):
            pass

        print(f"mandarin_readings_merged: {total:,} 条")
        if supplemented:
            print(f"  merge 后补充: {', '.join(supplemented)}")
        print(f"  合并列: {', '.join(MANDARIN_SOURCE_COLUMNS)}")
        print(f"  is_single=1: {single_count:,}, is_single=0: {total - single_count:,}")
        for source, count in sorted(source_counts.items()):
            print(f"  common_reading_source={source}: {count:,}")
        print(f"数据库: {DB_PATH}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
