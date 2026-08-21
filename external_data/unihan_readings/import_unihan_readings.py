#!/usr/bin/env python3
import sqlite3
import sys
from pathlib import Path
from typing import Dict, Optional

SCRIPT_DIR = Path(__file__).resolve().parent
HANZI_PINYIN_DIR = SCRIPT_DIR.parents[1] / "internal_data" / "hanzi_pinyin"
sys.path.insert(0, str(HANZI_PINYIN_DIR))

from hanzi_catalog import ensure_hanzi_catalog  # noqa: E402
from pinyin_match import MANDARIN_SOURCE_COLUMNS  # noqa: E402

UNIHAN_PATH = SCRIPT_DIR / "Unihan_Readings.txt"
DB_PATH = SCRIPT_DIR / "unihan_readings.db"

MANDARIN_FIELDS = frozenset(MANDARIN_SOURCE_COLUMNS)
COLUMNS = ["codepoint", *MANDARIN_SOURCE_COLUMNS]


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
    cur.execute("DROP TABLE IF EXISTS mandarin_readings_mode_diff")
    cur.execute("DROP TABLE IF EXISTS readings_mode_hanzi_pinyin_diff")
    conn.commit()


def parse_unihan_line(line: str) -> Optional[Dict[str, str]]:
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = line.split("\t", 2)
    if len(parts) < 3:
        return None
    codepoint, field, value = parts
    if not codepoint.startswith("U+"):
        return None
    if field not in MANDARIN_FIELDS:
        return None
    return {"codepoint": codepoint, field: value}


def clean_tghz_xhc_pinyin(value: str) -> str:
    parts = value.split()
    cleaned = []
    for part in parts:
        part = part.strip()
        if ":" in part:
            pinyin_part = part.split(":", 1)[1].strip()
            cleaned.append(pinyin_part)
        else:
            cleaned.append(part)
    return ",".join(cleaned)


def clean_hypl_pinyin(value: str) -> str:
    parts = value.split()
    cleaned = []
    for part in parts:
        if "(" in part:
            cleaned.append(part.split("(", 1)[0])
        else:
            cleaned.append(part)
    return ",".join(cleaned)


def clean_mandarin_pinyin(value: str) -> str:
    segments = value.split(";")
    cleaned = []
    for seg in segments:
        seg = seg.strip()
        if not seg:
            continue
        cleaned.append(",".join(seg.split()))
    return ";".join(cleaned)


def create_tables(conn: sqlite3.Connection) -> None:
    drop_unihan_reading_objects(conn)
    cur = conn.cursor()
    reading_columns_sql = ",\n    ".join(f"{col} TEXT" for col in MANDARIN_SOURCE_COLUMNS)
    table_sql = f"""
        CREATE TABLE {{table_name}} (
            codepoint TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            {reading_columns_sql}
        )
    """
    cur.execute(table_sql.format(table_name="unihan_readings_raw"))
    cur.execute(table_sql.format(table_name="unihan_readings_clean"))
    conn.commit()


def import_unihan() -> None:
    if not UNIHAN_PATH.exists():
        raise FileNotFoundError(f"Unihan_Readings.txt 未找到: {UNIHAN_PATH}")

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    hanzi_total = ensure_hanzi_catalog(conn)
    print(f"hanzi 主表: {hanzi_total:,} 条")
    create_tables(conn)
    cur = conn.cursor()
    known_codepoints = {
        row[0] for row in cur.execute("SELECT codepoint FROM hanzi")
    }

    raw_data: Dict[str, Dict[str, str]] = {}
    with open(UNIHAN_PATH, "r", encoding="utf-8") as f:
        for line in f:
            parsed = parse_unihan_line(line)
            if not parsed:
                continue
            cp = parsed["codepoint"]
            if cp not in raw_data:
                raw_data[cp] = {col: None for col in COLUMNS}
                raw_data[cp]["codepoint"] = cp
            for field, value in parsed.items():
                if field == "codepoint":
                    continue
                existing = raw_data[cp].get(field)
                if existing:
                    raw_data[cp][field] = existing + ";" + value
                else:
                    raw_data[cp][field] = value

    skipped = 0
    inserted = 0
    placeholders = ",".join("?" * len(COLUMNS))
    for cp, row in raw_data.items():
        if cp not in known_codepoints:
            skipped += 1
            continue
        cur.execute(
            f"INSERT INTO unihan_readings_raw VALUES ({placeholders})",
            tuple(row[col] for col in COLUMNS),
        )
        clean_row = row.copy()
        for col in ("kTGHZ2013", "kXHC1983", "kHanyuPinyin"):
            if clean_row[col]:
                clean_row[col] = clean_tghz_xhc_pinyin(clean_row[col])
        if clean_row["kHanyuPinlu"]:
            clean_row["kHanyuPinlu"] = clean_hypl_pinyin(clean_row["kHanyuPinlu"])
        if clean_row["kMandarin"]:
            clean_row["kMandarin"] = clean_mandarin_pinyin(clean_row["kMandarin"])
        cur.execute(
            f"INSERT INTO unihan_readings_clean VALUES ({placeholders})",
            tuple(clean_row[col] for col in COLUMNS),
        )
        inserted += 1

    conn.commit()
    conn.close()
    print(f"导入完成: {inserted:,} 条 Unihan 记录")
    if skipped:
        print(f"跳过: {skipped:,} 条（码点不在 hanzi 主表）")
    print(f"数据库: {DB_PATH}")
    print("原始表: unihan_readings_raw（五列普通话，kHanyuPinlu 保留频度）")
    print(
        "清理表: unihan_readings_clean "
        f"（{', '.join(MANDARIN_SOURCE_COLUMNS)}，已清洗）"
    )


if __name__ == "__main__":
    import_unihan()
