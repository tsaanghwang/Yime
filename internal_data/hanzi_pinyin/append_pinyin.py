#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path
from typing import Iterable

import sqlite3
from yime.utils.marked_pinyin import marked_syllable_to_numeric


BREVE_TO_CARON: dict[str, str] = {
    "ă": "ǎ",
    "Ă": "Ǎ",
    "ĕ": "ě",
    "Ĕ": "Ě",
    "ĭ": "ǐ",
    "Ĭ": "Ǐ",
    "ŏ": "ǒ",
    "Ŏ": "Ǒ",
    "ŭ": "ǔ",
    "Ŭ": "Ǔ",
}

SPECIAL_SINGLE_SYLLABLE_PY: dict[str, str] = {
    "U+26B22": "pú",
    "U+5159": "shí",
    "U+515B": "qiān",
    "U+515D": "fēn",
    "U+515E": "háo",
    "U+5161": "bǎi",
    "U+5163": "gōng",
    "U+55E7": "jiā",
    "U+74E7": "shí",
    "U+74E9": "qiān",
    "U+74F0": "fēn",
    "U+74F1": "máo",
    "U+74F2": "tún",
    "U+74FC": "lǐ",
    "U+7505": "lí",
}

TONE_MARK_CHARS = "āáǎàēéěèếềīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ̄́̌̀"


def normalize_pinyin_candidate(value: str) -> str:
    value = unicodedata.normalize("NFC", value.strip())
    if not value:
        return value
    chars = [BREVE_TO_CARON.get(ch, ch) for ch in value]
    value = "".join(chars)
    return unicodedata.normalize("NFC", value)



def merge_pinyins(existing: list[str], additions: Iterable[str]) -> list[str]:
    # Normalize inputs and preserve order, deduplicate
    def norm(s: str) -> str:
        return normalize_pinyin_candidate(s)

    result: list[str] = []
    seen: set[str] = set()
    for p in existing:
        np = norm(p)
        if np not in seen:
            seen.add(np)
            result.append(np)
    for p in additions:
        np = norm(p)
        if np not in seen:
            seen.add(np)
            result.append(np)
    return result


def strip_tone_marks(value: str) -> str:
    normalized = normalize_pinyin_candidate(value)
    decomposed = unicodedata.normalize("NFD", normalized)
    stripped = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return unicodedata.normalize("NFC", stripped)


def has_tonal_equivalent(plain_untoned: str, candidates: Iterable[str]) -> bool:
    plain_norm = normalize_pinyin_candidate(plain_untoned)
    for candidate in candidates:
        candidate_norm = normalize_pinyin_candidate(candidate)
        if any(char in TONE_MARK_CHARS for char in candidate_norm):
            if strip_tone_marks(candidate_norm) == plain_norm:
                return True
    return False


def filter_nonstandard_candidates(
    candidates: Iterable[str],
    valid_plain_untoned: set[str],
    valid_numeric: set[str],
) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for p in candidates:
        normalized = normalize_pinyin_candidate(p)
        if not normalized:
            continue
        if not any(char in TONE_MARK_CHARS for char in normalized):
            if is_nonstandard_pinyin(normalized, valid_plain_untoned):
                continue
            if has_tonal_equivalent(normalized, candidates):
                continue
        elif is_toned_but_outside_codebook(normalized, valid_numeric):
            continue
        if normalized not in seen:
            seen.add(normalized)
            result.append(normalized)
    return result


def is_multi_syllable_pinyin(value: str) -> bool:
    return len(re.findall(r"[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]", value)) > 1


def apply_special_single_syllable_policy(codepoint: str, candidates: list[str]) -> list[str]:
    if codepoint not in SPECIAL_SINGLE_SYLLABLE_PY:
        return candidates

    chosen = SPECIAL_SINGLE_SYLLABLE_PY[codepoint]
    return [chosen]



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


def load_validated_pinyin(path: Path) -> dict[str, list[str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    validated: dict[str, list[str]] = {}
    for codepoint, candidates in payload.items():
        if not isinstance(codepoint, str) or not isinstance(candidates, list):
            continue
        normalized_candidates: list[str] = []
        for candidate in candidates:
            if not isinstance(candidate, str):
                continue
            normalized = normalize_pinyin_candidate(candidate)
            if normalized and normalized not in normalized_candidates:
                normalized_candidates.append(normalized)
        if normalized_candidates:
            validated[codepoint.upper()] = normalized_candidates
    return validated


def is_toned_but_outside_codebook(value: str, valid_numeric: set[str]) -> bool:
    if not any(char in TONE_MARK_CHARS for char in value):
        return False
    return marked_syllable_to_numeric(value) not in valid_numeric


def is_nonstandard_pinyin(value: str, valid_plain_untoned: set[str]) -> bool:
    value = normalize_pinyin_candidate(value)
    if any(char in TONE_MARK_CHARS for char in value):
        return False
    return value not in valid_plain_untoned



def build_report(changes: list[tuple[str, str, list[str]]]) -> str:
    lines = [
        f"updated_rows: {len(changes)}",
        "" if not changes else "examples:",
    ]
    for codepoint, hanzi, added in changes[:20]:
        lines.append(f"{codepoint} {hanzi}: added {added}")
    return "\n".join(line for line in lines if line)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Merge validated pinyin from pinyin_source_staging + validated_pinyin.json into hanzi_pinyin."
    )
    parser.add_argument(
        "--db",
        default=str(Path(__file__).resolve().with_name("hanzi_pinyin.db")),
        help="Target hanzi_pinyin.db path",
    )
    parser.add_argument(
        "--validated",
        default=str(Path(__file__).resolve().parent / "validated_pinyin.json"),
        help="Validated pinyin candidate JSON path produced by filter_invalid_pinyin.py",
    )
    parser.add_argument(
        "--pinyin-normalized",
        default=str(Path(__file__).resolve().parents[2] / "internal_data" / "pinyin_source_db" / "lexicon_exports" / "pinyin_normalized.json"),
        help="Validated pinyin_normalized.json path used to identify valid plain untoned pinyin",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write back changes, only report differences",
    )
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")

    validated_path = Path(args.validated)
    if not validated_path.exists():
        raise FileNotFoundError(f"validated candidate file not found: {validated_path}")

    normalized_path = Path(args.pinyin_normalized)
    if not normalized_path.exists():
        raise FileNotFoundError(f"pinyin_normalized.json not found: {normalized_path}")
    valid_plain_untoned = load_valid_plain_untoned_pinyin(normalized_path)
    valid_numeric = load_valid_numeric_pinyin(normalized_path)

    validated_map = load_validated_pinyin(validated_path)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("SELECT codepoint, hanzi, common_reading, readings FROM hanzi_pinyin")
    existing_rows: dict[str, dict[str, str]] = {}
    for codepoint, hanzi, common_reading, readings in cur.fetchall():
        existing_rows[codepoint] = {
            "codepoint": codepoint,
            "hanzi": hanzi,
            "common_reading": common_reading or "",
            "readings": readings or "",
        }

    report_changes: list[tuple[str, str, list[str]]] = []
    update_rows: list[tuple[str, str, str]] = []

    for codepoint, row in existing_rows.items():
        existing_readings = row["readings"]
        existing_candidates = [p.strip() for p in existing_readings.split(",") if p.strip()] if existing_readings.strip() else []

        validated_candidates = validated_map.get(codepoint, [])

        additions: list[str] = []
        filtered = filter_nonstandard_candidates(
            validated_candidates,
            valid_plain_untoned,
            valid_numeric,
        )
        for p in filtered:
            if p not in additions:
                additions.append(p)

        if not additions:
            continue

        merged_candidates = merge_pinyins(existing_candidates, additions)
        merged_candidates = apply_special_single_syllable_policy(codepoint, merged_candidates)

        if merged_candidates == existing_candidates:
            continue

        primary_norm = merged_candidates[0]
        if is_nonstandard_pinyin(primary_norm, valid_plain_untoned):
            primary_norm = ""
        if codepoint in SPECIAL_SINGLE_SYLLABLE_PY:
            primary_norm = SPECIAL_SINGLE_SYLLABLE_PY[codepoint]
        if not primary_norm and merged_candidates:
            primary_norm = merged_candidates[0]

        merged_readings = ",".join(merged_candidates)
        update_rows.append((primary_norm, merged_readings, codepoint))

        added = [p for p in merged_candidates if p not in existing_candidates]
        if added:
            report_changes.append((codepoint, row.get("hanzi", ""), added))

    if update_rows:
        if not args.dry_run:
            cur.executemany(
                "UPDATE hanzi_pinyin SET common_reading = ?, readings = ? WHERE codepoint = ?",
                update_rows,
            )
            conn.commit()
        if report_changes:
            print(build_report(report_changes))
        else:
            print(f"updated {len(update_rows)} rows (normalization only)")
    else:
        print("no new pinyin candidates to merge")

    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
