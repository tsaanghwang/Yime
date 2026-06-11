#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path
from typing import Iterable

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

TONE_MARK_CHARS = "āáǎàēéěèếềīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ̄́̌̀"


def normalize_pinyin_candidate(value: str) -> str:
    value = unicodedata.normalize("NFC", value.strip())
    if not value:
        return value
    chars = [BREVE_TO_CARON.get(ch, ch) for ch in value]
    value = "".join(chars)
    return unicodedata.normalize("NFC", value)


def parse_pinyin_source(path: Path) -> dict[str, list[str]]:
    pinyin_map: dict[str, list[str]] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
        if not line:
            continue

        if ":" not in line:
            continue

        codepoint, pinyin_text = line.split(":", 1)
        codepoint = codepoint.strip().upper()
        if not codepoint.startswith("U+"):
            continue

        pinyin_list = [normalize_pinyin_candidate(p) for p in parse_pinyin_list(pinyin_text)]
        if not pinyin_list:
            continue

        existing = pinyin_map.setdefault(codepoint, [])
        for p in pinyin_list:
            if p not in existing:
                existing.append(p)
    return pinyin_map


def parse_pinyin_list(raw: str) -> list[str]:
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"'):
        raw = raw[1:-1]
    raw = raw.strip()
    if not raw:
        return []
    return [normalize_pinyin_candidate(item.strip()) for item in raw.split(",") if item.strip()]


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


def is_toned_but_outside_codebook(value: str, valid_numeric: set[str]) -> bool:
    if not any(char in TONE_MARK_CHARS for char in value):
        return False
    return marked_syllable_to_numeric(value) not in valid_numeric


def is_nonstandard_pinyin(value: str, valid_plain_untoned: set[str]) -> bool:
    value = normalize_pinyin_candidate(value)
    if any(char in TONE_MARK_CHARS for char in value):
        return False
    return value not in valid_plain_untoned


def load_staging_pinyin(db_path: Path) -> dict[str, list[str]]:
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    staging_map: dict[str, list[str]] = {}
    for codepoint, readings in cur.execute("SELECT codepoint, readings FROM pinyin_source_staging"):
        if readings and readings.strip():
            candidates = [normalize_pinyin_candidate(p) for p in readings.split(",") if p.strip()]
            if candidates:
                staging_map[codepoint.upper()] = candidates
    conn.close()
    return staging_map


def build_validation_results(
    source_maps: Iterable[tuple[str, dict[str, list[str]]]],
    valid_plain_untoned: set[str],
    valid_numeric: set[str],
) -> tuple[dict[str, list[str]], dict[str, list[dict[str, str]]]]:
    validated: dict[str, list[str]] = {}
    invalid: dict[str, list[dict[str, str]]] = {}

    for source_name, source_map in source_maps:
        for codepoint, candidates in source_map.items():
            codepoint = codepoint.upper()
            for candidate in candidates:
                normalized = normalize_pinyin_candidate(candidate)
                if not normalized:
                    reason = "empty"
                elif not any(char in TONE_MARK_CHARS for char in normalized):
                    if is_nonstandard_pinyin(normalized, valid_plain_untoned):
                        reason = "invalid_plain_untoned"
                    elif has_tonal_equivalent(normalized, candidates):
                        reason = "duplicate_with_tonal_equivalent"
                    else:
                        reason = "valid"
                elif is_toned_but_outside_codebook(normalized, valid_numeric):
                    reason = "toned_outside_codebook"
                else:
                    reason = "valid"

                if reason != "valid":
                    bucket = invalid.setdefault(codepoint, [])
                    if not any(
                        item["candidate"] == normalized
                        and item["reason"] == reason
                        and item["source"] == source_name
                        for item in bucket
                    ):
                        bucket.append({"candidate": normalized, "reason": reason, "source": source_name})
                    continue

                bucket = validated.setdefault(codepoint, [])
                if normalized not in bucket:
                    bucket.append(normalized)

    return validated, invalid


def write_json_file(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_report(validated: dict[str, list[str]], invalid: dict[str, list[dict[str, str]]]) -> str:
    lines = [
        f"validated_codepoints: {len(validated)}",
        f"invalid_codepoints: {len(invalid)}",
        "",
    ]
    if validated:
        lines.append("validated examples:")
        for codepoint, items in sorted(validated.items())[:20]:
            lines.append(f"{codepoint}: {items}")
        lines.append("")
    if invalid:
        lines.append("invalid examples:")
        for codepoint, items in sorted(invalid.items())[:20]:
            lines.append(f"{codepoint}: {items}")
    return "\n".join(line for line in lines if line)



def main() -> int:
    parser = argparse.ArgumentParser(
        description="Filter invalid pinyin from pinyin_source_staging table or external files, then export qualified candidates."
    )
    parser.add_argument(
        "--db",
        default=str(Path(__file__).resolve().with_name("hanzi_pinyin.db")),
        help="Source hanzi_pinyin.db path (reads from pinyin_source_staging table)",
    )
    source_group = parser.add_mutually_exclusive_group()
    source_group.add_argument(
        "--from-staging",
        action="store_true",
        default=True,
        help="Read from pinyin_source_staging table in DB [default]",
    )
    source_group.add_argument(
        "--from-files",
        action="store_true",
        help="Read from external pinyin.txt and/or zdic.txt files",
    )
    parser.add_argument(
        "--pinyin",
        default=str(Path(__file__).resolve().parents[2] / "external_data" / "pinyin.txt"),
        help="Source pinyin.txt file path (used with --from-files)",
    )
    parser.add_argument(
        "--zdic",
        default=str(Path(__file__).resolve().parents[2] / "external_data" / "zdic.txt"),
        help="Source zdic.txt file path (used with --from-files)",
    )
    parser.add_argument(
        "--pinyin-normalized",
        default=str(Path(__file__).resolve().parents[2] / "internal_data" / "pinyin_source_db" / "lexicon_exports" / "pinyin_normalized.json"),
        help="Validated pinyin_normalized.json path used to identify valid plain untoned pinyin",
    )
    parser.add_argument(
        "--output",
        default=str(Path(__file__).resolve().parent / "validated_pinyin.json"),
        help="Output JSON path for validated pinyin candidates",
    )
    parser.add_argument(
        "--invalid-output",
        default=str(Path(__file__).resolve().parent / "invalid_pinyin.json"),
        help="Output JSON path for invalid pinyin candidates",
    )
    args = parser.parse_args()

    normalized_path = Path(args.pinyin_normalized)
    if not normalized_path.exists():
        raise FileNotFoundError(f"pinyin_normalized.json not found: {normalized_path}")
    valid_plain_untoned = load_valid_plain_untoned_pinyin(normalized_path)
    valid_numeric = load_valid_numeric_pinyin(normalized_path)

    source_maps: list[tuple[str, dict[str, list[str]]]] = []

    if args.from_files:
        pinyin_path = Path(args.pinyin)
        if pinyin_path.exists():
            source_maps.append(("pinyin", parse_pinyin_source(pinyin_path)))
        zdic_path = Path(args.zdic)
        if zdic_path.exists():
            source_maps.append(("zdic", parse_pinyin_source(zdic_path)))
        if not source_maps:
            raise FileNotFoundError("no external source files found")
    else:
        db_path = Path(args.db)
        if not db_path.exists():
            raise FileNotFoundError(f"database file not found: {db_path}")
        staging_map = load_staging_pinyin(db_path)
        if not staging_map:
            print("pinyin_source_staging table is empty; import data first with pinyin_source_staging.py")
            return 1
        source_maps.append(("staging", staging_map))

    validated_map, invalid_map = build_validation_results(
        source_maps, valid_plain_untoned, valid_numeric
    )

    output_path = Path(args.output)
    invalid_output_path = Path(args.invalid_output)
    write_json_file(output_path, validated_map)
    write_json_file(invalid_output_path, invalid_map)
    print(build_report(validated_map, invalid_map))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
