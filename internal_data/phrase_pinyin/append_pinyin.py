#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sqlite3
import unicodedata
from pathlib import Path

TONE_MARK_CHARS = "āáǎàēéěèếềīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ̄́̌̀"

BREVE_TO_CARON: dict[str, str] = {
    "ă": "ǎ", "Ă": "Ǎ",
    "ĕ": "ě", "Ĕ": "Ě",
    "ĭ": "ǐ", "Ĭ": "Ǐ",
    "ŏ": "ǒ", "Ŏ": "Ǒ",
    "ŭ": "ǔ", "Ŭ": "Ǔ",
}


def normalize_pinyin_candidate(value: str) -> str:
    value = unicodedata.normalize("NFC", value.strip())
    if not value:
        return value
    chars = [BREVE_TO_CARON.get(ch, ch) for ch in value]
    return unicodedata.normalize("NFC", "".join(chars))


def split_syllables(pinyin_str: str) -> list[str]:
    return [normalize_pinyin_candidate(part) for part in pinyin_str.split() if part.strip()]


def load_valid_plain_untoned_pinyin(path: Path) -> set[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {
        key[:-1]
        for key in payload.keys()
        if isinstance(key, str) and key and key[-1] in "12345"
    }


def load_valid_numeric_pinyin(path: Path) -> set[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {key for key in payload.keys() if isinstance(key, str)}


def load_staging_readings(db_path: Path) -> dict[str, list[str]]:
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    readings_map: dict[str, list[str]] = {}
    for phrase, readings in cur.execute("SELECT phrase, readings FROM phrase_source_staging"):
        if readings and readings.strip():
            reading_list = [part.strip() for part in readings.split("|") if part.strip()]
            if reading_list:
                readings_map[phrase] = reading_list
    conn.close()
    return readings_map


def is_valid_syllable(
    syllable: str,
    valid_numeric: set[str],
    valid_plain_untoned: set[str],
) -> tuple[bool, str]:
    from yime.utils.marked_pinyin import marked_syllable_to_numeric

    numeric = marked_syllable_to_numeric(syllable)
    has_tone = any(ch in TONE_MARK_CHARS for ch in syllable)
    if has_tone:
        if numeric in valid_numeric:
            return True, ""
        return False, "toned_outside_codebook"
    if syllable in valid_plain_untoned:
        return True, ""
    return False, "nonstandard_untoned"


def validate_readings(
    staging_map: dict[str, list[str]],
    valid_numeric: set[str],
    valid_plain_untoned: set[str],
) -> tuple[dict[str, list[str]], dict[str, list[dict[str, str]]]]:
    validated: dict[str, list[str]] = {}
    invalid: dict[str, list[dict[str, str]]] = {}

    for phrase, reading_list in staging_map.items():
        valid_readings: list[str] = []
        for reading in reading_list:
            invalid_items: list[dict[str, str]] = []
            for syllable in split_syllables(reading):
                ok, reason = is_valid_syllable(syllable, valid_numeric, valid_plain_untoned)
                if not ok:
                    invalid_items.append({"syllable": syllable, "reason": reason})
            if invalid_items:
                bucket = invalid.setdefault(phrase, [])
                for item in invalid_items:
                    if not any(
                        existing["syllable"] == item["syllable"]
                        and existing["reason"] == item["reason"]
                        for existing in bucket
                    ):
                        bucket.append(item)
            else:
                valid_readings.append(reading)
        if valid_readings:
            validated[phrase] = valid_readings

    return validated, invalid


def build_report(validated: dict[str, list[str]], invalid: dict[str, list[dict[str, str]]]) -> str:
    lines = [
        f"validated_phrases: {len(validated):,}",
        f"invalid_phrases: {len(invalid):,}",
    ]
    if invalid:
        lines.append("invalid examples:")
        for phrase, items in sorted(invalid.items())[:5]:
            lines.append(f"  {phrase}: {items}")
    return "\n".join(lines)


def append_validated_pinyin(
    db_path: Path,
    validated: dict[str, list[str]],
) -> int:
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DELETE FROM phrase_pinyin")
    rows = [
        (phrase, len(phrase), reading_list[0], "|".join(reading_list))
        for phrase, reading_list in validated.items()
        if reading_list
    ]
    if rows:
        cur.executemany(
            "INSERT INTO phrase_pinyin (phrase, phrase_len, common_reading, readings) VALUES (?, ?, ?, ?)",
            rows,
        )
    conn.commit()
    conn.close()
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate phrase_source_staging against Yime syllable codebook and load phrase_pinyin.",
    )
    parser.add_argument(
        "--db",
        default=str(Path(__file__).resolve().with_name("phrase_pinyin.db")),
        help="Target phrase_pinyin.db path",
    )
    parser.add_argument(
        "--pinyin-normalized",
        default=str(
            Path(__file__).resolve().parents[1]
            / "pinyin_source_db"
            / "lexicon_exports"
            / "pinyin_normalized.json"
        ),
        help="Validated pinyin_normalized.json path",
    )
    args = parser.parse_args()

    normalized_path = Path(args.pinyin_normalized)
    if not normalized_path.exists():
        raise FileNotFoundError(f"pinyin_normalized.json not found: {normalized_path}")

    db_path = Path(args.db)
    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")

    staging_map = load_staging_readings(db_path)
    if not staging_map:
        print("phrase_source_staging table is empty; import data first with phrase_source_staging.py")
        return 1

    validated_map, invalid_map = validate_readings(
        staging_map,
        load_valid_numeric_pinyin(normalized_path),
        load_valid_plain_untoned_pinyin(normalized_path),
    )

    loaded = append_validated_pinyin(db_path, validated_map)
    print(build_report(validated_map, invalid_map))
    print(f"loaded {loaded:,} rows -> phrase_pinyin")
    print(f"数据库: {db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
