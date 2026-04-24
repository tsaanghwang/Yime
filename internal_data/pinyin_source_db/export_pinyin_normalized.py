from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict, OrderedDict
from pathlib import Path

from build_source_pinyin_db import DEFAULT_DB_PATH
from validate_source_pinyin_db import (
    finalize_report,
    make_report,
    validate_single_char_rows,
    validate_source_file_metadata,
)


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_OUTPUT_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export validated single-character source data to pinyin_normalized.json format."
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Output JSON path")
    parser.add_argument(
        "--allow-validation-warnings",
        action="store_true",
        help="Allow export even if validation emits warnings. Errors still block export.",
    )
    return parser.parse_args()


def validate_db_for_export(conn: sqlite3.Connection) -> dict:
    report = make_report(sample_limit=20)
    validate_source_file_metadata(conn, report)
    validate_single_char_rows(conn, report)
    return finalize_report(report)


def collect_numeric_to_marked_pairs(conn: sqlite3.Connection) -> dict[str, set[str]]:
    mapping: dict[str, set[str]] = defaultdict(set)
    query = """
        SELECT DISTINCT numeric_pinyin, marked_pinyin
        FROM single_char_readings
        ORDER BY numeric_pinyin, marked_pinyin
    """
    for numeric_pinyin, marked_pinyin in conn.execute(query):
        mapping[numeric_pinyin].add(marked_pinyin)
    return mapping


def build_export_mapping(numeric_to_marked: dict[str, set[str]]) -> OrderedDict[str, str]:
    conflicts = {
        numeric: sorted(marked_values)
        for numeric, marked_values in numeric_to_marked.items()
        if len(marked_values) != 1
    }
    if conflicts:
        conflict_preview = "; ".join(
            f"{numeric}: {values}"
            for numeric, values in list(conflicts.items())[:10]
        )
        raise ValueError(
            "Found numeric pinyin values with multiple marked-pinyin exports: "
            f"{conflict_preview}"
        )

    return OrderedDict(
        (numeric, next(iter(marked_values)))
        for numeric, marked_values in sorted(numeric_to_marked.items(), key=lambda item: item[0])
    )


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    output_path = Path(args.output)

    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")

    conn = sqlite3.connect(db_path)
    try:
        validation_report = validate_db_for_export(conn)
        if validation_report["summary"]["error_count"]:
            raise ValueError(
                "Refusing to export because source database validation has errors: "
                f"{validation_report['summary']['error_count']}"
            )
        if validation_report["summary"]["warning_count"] and not args.allow_validation_warnings:
            raise ValueError(
                "Refusing to export because source database validation has warnings. "
                "Re-run with --allow-validation-warnings if this is intentional."
            )

        numeric_to_marked = collect_numeric_to_marked_pairs(conn)
    finally:
        conn.close()

    export_mapping = build_export_mapping(numeric_to_marked)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(export_mapping, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"database: {db_path}")
    print(f"output: {output_path}")
    print(f"rows_exported: {len(export_mapping)}")
    print(f"validation_errors: {validation_report['summary']['error_count']}")
    print(f"validation_warnings: {validation_report['summary']['warning_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
