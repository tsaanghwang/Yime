"""Post-merge supplements for characters outside Unihan Mandarin columns."""

from __future__ import annotations

import json
import sqlite3
import unicodedata
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_COMPLIANCE_POLICY_PATH = (
    REPO_ROOT
    / "internal_data"
    / "pinyin_source_db"
    / "dictionary_pinyin_compliance_policy.json"
)

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


def _compatibility_reading_aliases() -> dict[str, dict[str, str]]:
    payload = json.loads(
        SOURCE_COMPLIANCE_POLICY_PATH.read_text(encoding="utf-8")
    )
    aliases = payload.get("source_aliases", {})
    if not isinstance(aliases, dict):
        raise ValueError("source_aliases must be an object")
    validated: dict[str, dict[str, str]] = {}
    for raw_codepoint, raw_record in aliases.items():
        codepoint = str(raw_codepoint).upper()
        record = dict(raw_record)
        canonical_codepoint = str(record.get("canonical_codepoint", "")).upper()
        if not codepoint.startswith("U+") or not canonical_codepoint.startswith("U+"):
            raise ValueError("compatibility alias codepoints must use U+ notation")
        source_char = chr(int(codepoint[2:], 16))
        target_char = chr(int(canonical_codepoint[2:], 16))
        normalized = unicodedata.normalize("NFKC", source_char)
        if normalized != target_char:
            raise ValueError(
                f"{codepoint} does not normalize exactly to {canonical_codepoint}"
            )
        if not str(record.get("rule_id", "")).strip():
            raise ValueError(f"{codepoint} compatibility alias lacks rule_id")
        validated[codepoint] = {
            "canonical_codepoint": canonical_codepoint,
            "rule_id": str(record["rule_id"]),
        }
    return validated


def apply_compatibility_reading_aliases(cur: sqlite3.Cursor) -> list[str]:
    """Copy attested readings through reviewed one-to-one Unicode mappings."""
    applied: list[str] = []
    for codepoint, record in _compatibility_reading_aliases().items():
        existing = cur.execute(
            "SELECT readings FROM mandarin_readings_merged WHERE codepoint = ?",
            (codepoint,),
        ).fetchone()
        if existing is not None and existing[0] and str(existing[0]).strip():
            continue
        canonical_codepoint = record["canonical_codepoint"]
        canonical = cur.execute(
            """
            SELECT readings, common_reading, is_single
            FROM mandarin_readings_merged
            WHERE codepoint = ?
            """,
            (canonical_codepoint,),
        ).fetchone()
        if canonical is None or not canonical[0] or not str(canonical[0]).strip():
            raise ValueError(
                f"{codepoint} alias target has no merged reading: "
                f"{canonical_codepoint}"
            )
        hanzi_row = cur.execute(
            "SELECT hanzi FROM hanzi WHERE codepoint = ?",
            (codepoint,),
        ).fetchone()
        if hanzi_row is None:
            raise ValueError(f"compatibility alias is outside hanzi catalog: {codepoint}")
        values = (
            str(hanzi_row[0]),
            str(canonical[0]),
            str(canonical[1]),
            f"compatibility_alias:{canonical_codepoint}",
            int(canonical[2]),
            codepoint,
        )
        if existing is None:
            cur.execute(
                """
                INSERT INTO mandarin_readings_merged (
                    hanzi, readings, common_reading, common_reading_source,
                    is_single, codepoint
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                values,
            )
        else:
            cur.execute(
                """
                UPDATE mandarin_readings_merged
                SET hanzi = ?, readings = ?, common_reading = ?,
                    common_reading_source = ?, is_single = ?
                WHERE codepoint = ?
                """,
                values,
            )
        applied.append(codepoint)
    return applied


def apply_merged_supplements(cur: sqlite3.Cursor) -> list[str]:
    """Run all post-merge supplements; return labels of applied items."""
    applied: list[str] = []
    if apply_zero_digit_reading_supplement(cur):
        applied.append(ZERO_DIGIT_CODEPOINT)
    applied.extend(apply_compatibility_reading_aliases(cur))
    return applied
