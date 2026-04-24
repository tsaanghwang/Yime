from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import Any

from build_source_pinyin_db import DEFAULT_DB_PATH, marked_phrase_to_numeric, marked_syllable_to_numeric


CODEPOINT_RE = re.compile(r"^U\+[0-9A-F]{4,6}$")
NUMERIC_SYLLABLE_RE = re.compile(r"^[a-zêü]+[1-5]$")
MARKED_ALLOWED_RE = re.compile(r"^[a-zêüāáǎàēéěèếềīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ̄́̌̀]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the source pinyin SQLite database.")
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument(
        "--output",
        default="",
        help="Optional JSON report output path. Defaults to <db_dir>/validation_report.json",
    )
    parser.add_argument(
        "--sample-limit",
        type=int,
        default=20,
        help="Maximum number of example issues to keep per category",
    )
    return parser.parse_args()


def make_report(sample_limit: int) -> dict[str, Any]:
    return {
        "summary": {
            "single_char_rows": 0,
            "phrase_rows": 0,
            "error_count": 0,
            "warning_count": 0,
        },
        "errors": defaultdict(list),
        "warnings": defaultdict(list),
        "sample_limit": sample_limit,
    }


def record_issue(report: dict[str, Any], level: str, category: str, detail: dict[str, Any]) -> None:
    summary_key = "error_count" if level == "errors" else "warning_count"
    report["summary"][summary_key] += 1
    if len(report[level][category]) < report["sample_limit"]:
        report[level][category].append(detail)


def codepoint_to_char(codepoint: str) -> str | None:
    if not CODEPOINT_RE.match(codepoint):
        return None
    return chr(int(codepoint[2:], 16))


def validate_single_char_rows(conn: sqlite3.Connection, report: dict[str, Any]) -> None:
    query = """
        SELECT id, source_name, codepoint, hanzi, marked_pinyin, numeric_pinyin, reading_rank, is_primary
        FROM single_char_readings
        ORDER BY id
    """
    primary_counts: dict[tuple[str, str], int] = defaultdict(int)

    for row in conn.execute(query):
        row_id, source_name, codepoint, hanzi, marked_pinyin, numeric_pinyin, reading_rank, is_primary = row
        report["summary"]["single_char_rows"] += 1
        key = (source_name, codepoint)
        primary_counts[key] += int(bool(is_primary))

        if not CODEPOINT_RE.match(codepoint):
            record_issue(report, "errors", "invalid_codepoint_format", {
                "id": row_id,
                "codepoint": codepoint,
                "hanzi": hanzi,
            })
            continue

        expected_hanzi = codepoint_to_char(codepoint)
        if expected_hanzi != hanzi:
            record_issue(report, "errors", "codepoint_hanzi_mismatch", {
                "id": row_id,
                "codepoint": codepoint,
                "hanzi": hanzi,
                "expected_hanzi": expected_hanzi,
            })

        if any(char.isdigit() for char in marked_pinyin):
            record_issue(report, "errors", "marked_pinyin_contains_digit", {
                "id": row_id,
                "marked_pinyin": marked_pinyin,
            })

        if "v" in marked_pinyin.lower():
            record_issue(report, "errors", "marked_pinyin_contains_technical_v", {
                "id": row_id,
                "marked_pinyin": marked_pinyin,
            })

        if not MARKED_ALLOWED_RE.match(marked_pinyin):
            record_issue(report, "warnings", "marked_pinyin_has_unexpected_chars", {
                "id": row_id,
                "marked_pinyin": marked_pinyin,
            })

        expected_numeric = marked_syllable_to_numeric(marked_pinyin)
        if numeric_pinyin != expected_numeric:
            record_issue(report, "errors", "numeric_pinyin_mismatch", {
                "id": row_id,
                "marked_pinyin": marked_pinyin,
                "numeric_pinyin": numeric_pinyin,
                "expected_numeric": expected_numeric,
            })

        if not NUMERIC_SYLLABLE_RE.match(numeric_pinyin):
            record_issue(report, "errors", "invalid_numeric_pinyin_format", {
                "id": row_id,
                "numeric_pinyin": numeric_pinyin,
            })

        if reading_rank < 1:
            record_issue(report, "errors", "invalid_reading_rank", {
                "id": row_id,
                "reading_rank": reading_rank,
            })

        if is_primary not in (0, 1):
            record_issue(report, "errors", "invalid_is_primary_flag", {
                "id": row_id,
                "is_primary": is_primary,
            })

    for (source_name, codepoint), count in primary_counts.items():
        if count != 1:
            record_issue(report, "errors", "primary_reading_count_violation", {
                "source_name": source_name,
                "codepoint": codepoint,
                "primary_count": count,
            })


def validate_phrase_rows(conn: sqlite3.Connection, report: dict[str, Any]) -> None:
    query = """
        SELECT id, source_name, phrase, marked_pinyin, numeric_pinyin, reading_rank
        FROM phrase_readings
        ORDER BY id
    """
    for row in conn.execute(query):
        row_id, source_name, phrase, marked_pinyin, numeric_pinyin, reading_rank = row
        report["summary"]["phrase_rows"] += 1

        if any(char.isdigit() for char in marked_pinyin):
            record_issue(report, "errors", "phrase_marked_pinyin_contains_digit", {
                "id": row_id,
                "phrase": phrase,
                "marked_pinyin": marked_pinyin,
            })

        if "v" in marked_pinyin.lower():
            record_issue(report, "errors", "phrase_marked_pinyin_contains_technical_v", {
                "id": row_id,
                "phrase": phrase,
                "marked_pinyin": marked_pinyin,
            })

        expected_numeric = marked_phrase_to_numeric(marked_pinyin)
        if numeric_pinyin != expected_numeric:
            record_issue(report, "errors", "phrase_numeric_pinyin_mismatch", {
                "id": row_id,
                "phrase": phrase,
                "marked_pinyin": marked_pinyin,
                "numeric_pinyin": numeric_pinyin,
                "expected_numeric": expected_numeric,
            })

        syllables = numeric_pinyin.split()
        if not syllables or any(not NUMERIC_SYLLABLE_RE.match(syllable) for syllable in syllables):
            record_issue(report, "errors", "invalid_phrase_numeric_format", {
                "id": row_id,
                "phrase": phrase,
                "numeric_pinyin": numeric_pinyin,
            })

        if len(syllables) != len(phrase):
            record_issue(report, "warnings", "phrase_syllable_count_mismatch", {
                "id": row_id,
                "phrase": phrase,
                "syllable_count": len(syllables),
                "character_count": len(phrase),
                "numeric_pinyin": numeric_pinyin,
            })

        if reading_rank < 1:
            record_issue(report, "errors", "invalid_phrase_reading_rank", {
                "id": row_id,
                "reading_rank": reading_rank,
            })

        if source_name == "":
            record_issue(report, "errors", "missing_phrase_source_name", {"id": row_id, "phrase": phrase})


def validate_source_file_metadata(conn: sqlite3.Connection, report: dict[str, Any]) -> None:
    rows = list(conn.execute("SELECT source_name, source_kind, source_path FROM source_files ORDER BY source_name"))
    if not rows:
        record_issue(report, "errors", "missing_source_files_metadata", {"detail": "source_files table is empty"})
        return

    for source_name, source_kind, source_path in rows:
        if not Path(source_path).exists():
            record_issue(report, "warnings", "missing_source_path_on_disk", {
                "source_name": source_name,
                "source_kind": source_kind,
                "source_path": source_path,
            })


def finalize_report(report: dict[str, Any]) -> dict[str, Any]:
    report["errors"] = {key: value for key, value in sorted(report["errors"].items())}
    report["warnings"] = {key: value for key, value in sorted(report["warnings"].items())}
    return report


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    output_path = Path(args.output) if args.output else db_path.with_name("validation_report.json")

    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")

    report = make_report(args.sample_limit)

    conn = sqlite3.connect(db_path)
    try:
        validate_source_file_metadata(conn, report)
        validate_single_char_rows(conn, report)
        validate_phrase_rows(conn, report)
    finally:
        conn.close()

    finalized = finalize_report(report)
    output_path.write_text(json.dumps(finalized, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"database: {db_path}")
    print(f"report: {output_path}")
    print(f"single_char_rows: {finalized['summary']['single_char_rows']}")
    print(f"phrase_rows: {finalized['summary']['phrase_rows']}")
    print(f"errors: {finalized['summary']['error_count']}")
    print(f"warnings: {finalized['summary']['warning_count']}")

    return 1 if finalized["summary"]["error_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
