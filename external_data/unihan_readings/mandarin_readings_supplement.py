"""Post-merge supplements for characters outside Unihan Mandarin columns."""

from __future__ import annotations

import sqlite3

# 小写零字「〇」：辞书释为「零的空位」；Unihan 五列无普通话读音。
# 读音依据较新版本《新华字典》《现代汉语词典》，见 README.md。
ZERO_DIGIT_CODEPOINT = "U+3007"
ZERO_DIGIT_READINGS = "líng"
ZERO_DIGIT_COMMON_READING = "líng"
ZERO_DIGIT_SOURCE = "supplement"


def _merged_has_readings(cur: sqlite3.Cursor, codepoint: str) -> bool:
    row = cur.execute(
        "SELECT readings FROM mandarin_readings_merged WHERE codepoint = ?",
        (codepoint,),
    ).fetchone()
    return row is not None and bool(row[0] and str(row[0]).strip())


def apply_zero_digit_reading_supplement(cur: sqlite3.Cursor) -> bool:
    """若 merge 后 〇 (U+3007) 无拼音，写入硬编码读音与常用读音。"""
    if _merged_has_readings(cur, ZERO_DIGIT_CODEPOINT):
        return False

    hanzi_row = cur.execute(
        "SELECT hanzi FROM hanzi WHERE codepoint = ?",
        (ZERO_DIGIT_CODEPOINT,),
    ).fetchone()
    if hanzi_row is None:
        return False

    hanzi = hanzi_row[0]
    is_single = 0 if "," in ZERO_DIGIT_READINGS else 1
    exists = cur.execute(
        "SELECT 1 FROM mandarin_readings_merged WHERE codepoint = ?",
        (ZERO_DIGIT_CODEPOINT,),
    ).fetchone() is not None

    if exists:
        cur.execute(
            "UPDATE mandarin_readings_merged "
            "SET hanzi = ?, readings = ?, common_reading = ?, "
            "common_reading_source = ?, is_single = ? "
            "WHERE codepoint = ?",
            (
                hanzi,
                ZERO_DIGIT_READINGS,
                ZERO_DIGIT_COMMON_READING,
                ZERO_DIGIT_SOURCE,
                is_single,
                ZERO_DIGIT_CODEPOINT,
            ),
        )
    else:
        cur.execute(
            "INSERT INTO mandarin_readings_merged "
            "(codepoint, hanzi, readings, common_reading, common_reading_source, is_single) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                ZERO_DIGIT_CODEPOINT,
                hanzi,
                ZERO_DIGIT_READINGS,
                ZERO_DIGIT_COMMON_READING,
                ZERO_DIGIT_SOURCE,
                is_single,
            ),
        )
    return True


def apply_merged_supplements(cur: sqlite3.Cursor) -> list[str]:
    """Run all post-merge supplements; return labels of applied items."""
    applied: list[str] = []
    if apply_zero_digit_reading_supplement(cur):
        applied.append(ZERO_DIGIT_CODEPOINT)
    return applied
