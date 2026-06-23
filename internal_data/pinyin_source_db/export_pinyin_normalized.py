from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict, OrderedDict
from pathlib import Path
from typing import Any

from build_source_pinyin_db import DEFAULT_DB_PATH
from validate_source_pinyin_db import (
    finalize_report,
    make_report,
    validate_char_rows,
    validate_source_file_metadata,
)


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_OUTPUT_PATH = SCRIPT_DIR / "lexicon_exports" / "pinyin_normalized.json"
DEFAULT_CODEBOOK_PATH = WORKSPACE_ROOT / "syllable" / "codec" / "yinjie_code.json"
DEFAULT_SUPPLEMENTAL_PATCH_PATH = SCRIPT_DIR / "pinyin_normalized_patch.json"
DEFAULT_INVENTORY_TABLE = "m_distinct_syllable_inventory"

TONE_MARKS = {
    "a": {"1": "ā", "2": "á", "3": "ǎ", "4": "à"},
    "e": {"1": "ē", "2": "é", "3": "ě", "4": "è"},
    "ê": {"1": "ê̄", "2": "ế", "3": "ê̌", "4": "ề"},
    "i": {"1": "ī", "2": "í", "3": "ǐ", "4": "ì"},
    "m": {"1": "m̄", "2": "ḿ", "3": "m̌", "4": "m̀"},
    "n": {"1": "n̄", "2": "ń", "3": "ň", "4": "ǹ"},
    "o": {"1": "ō", "2": "ó", "3": "ǒ", "4": "ò"},
    "u": {"1": "ū", "2": "ú", "3": "ǔ", "4": "ù"},
    "ü": {"1": "ǖ", "2": "ǘ", "3": "ǚ", "4": "ǜ"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export validated char source data to pinyin_normalized.json format."
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Output JSON path")
    parser.add_argument("--codebook", default=str(DEFAULT_CODEBOOK_PATH), help="Reference yinjie codebook path")
    parser.add_argument(
        "--supplemental-patch",
        default=str(DEFAULT_SUPPLEMENTAL_PATCH_PATH),
        help="Optional JSON object of extra numeric_pinyin -> marked_pinyin pairs to include in the export domain",
    )
    parser.add_argument(
        "--inventory-table",
        default=DEFAULT_INVENTORY_TABLE,
        help=(
            "Materialized syllable inventory table used as the export domain "
            f"(default: {DEFAULT_INVENTORY_TABLE})."
        ),
    )
    parser.add_argument(
        "--export-domain",
        choices=("inventory", "codebook"),
        default="inventory",
        help=(
            "inventory: export every numeric syllable observed in the lexicon inventory "
            "(plus patch keys). codebook: legacy domain from yinjie_code.json keys only."
        ),
    )
    parser.add_argument(
        "--allow-validation-warnings",
        action="store_true",
        help="Allow export even if validation emits warnings. Errors still block export.",
    )
    return parser.parse_args()


def validate_db_for_export(conn: sqlite3.Connection) -> dict[str, Any]:
    report = make_report(sample_limit=20)
    validate_source_file_metadata(conn, report)
    validate_char_rows(conn, report)
    return finalize_report(report)


def quote_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def inventory_table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table_name,),
    ).fetchone()
    return row is not None


def load_inventory_numeric_syllables(conn: sqlite3.Connection, table_name: str) -> list[str]:
    if not inventory_table_exists(conn, table_name):
        raise ValueError(
            f"inventory table not found: {table_name}. "
            "Run tools/refresh_materialized_syllable_inventory.py first."
        )
    quoted_table = quote_identifier(table_name)
    query = f"""
        SELECT DISTINCT numeric_syllable
        FROM {quoted_table}
        WHERE TRIM(COALESCE(numeric_syllable, '')) <> ''
        ORDER BY numeric_syllable
    """
    return [row[0] for row in conn.execute(query)]


def collect_numeric_to_marked_pairs(
    conn: sqlite3.Connection,
    inventory_table: str,
) -> dict[str, set[str]]:
    mapping: dict[str, set[str]] = defaultdict(set)
    char_query = """
        SELECT DISTINCT numeric_pinyin, marked_pinyin
        FROM char_readings
        ORDER BY numeric_pinyin, marked_pinyin
    """
    char_numerics: set[str] = set()
    for numeric_pinyin, marked_pinyin in conn.execute(char_query):
        mapping[numeric_pinyin].add(marked_pinyin)
        char_numerics.add(numeric_pinyin)

    if not inventory_table_exists(conn, inventory_table):
        return mapping

    quoted_table = quote_identifier(inventory_table)
    phrase_only_query = f"""
        SELECT DISTINCT numeric_syllable, marked_syllable
        FROM {quoted_table}
        WHERE has_single_char = 0
          AND TRIM(COALESCE(numeric_syllable, '')) <> ''
          AND TRIM(COALESCE(marked_syllable, '')) <> ''
        ORDER BY numeric_syllable, marked_syllable
    """
    for numeric_syllable, marked_syllable in conn.execute(phrase_only_query):
        if numeric_syllable in char_numerics:
            continue
        mapping[numeric_syllable].add(marked_syllable)
    return mapping


def is_numeric_syllable_key(key: str) -> bool:
    return bool(key) and key[-1].isdigit()


def load_codebook_keys(path: Path) -> list[str]:
    all_keys = json.loads(path.read_text(encoding="utf-8")).keys()
    numeric_keys = sorted(key for key in all_keys if is_numeric_syllable_key(key))
    ignored = sorted(key for key in all_keys if not is_numeric_syllable_key(key))
    if ignored:
        preview = ", ".join(ignored[:8])
        suffix = "..." if len(ignored) > 8 else ""
        print(
            f"codebook_non_numeric_keys_ignored: {len(ignored)} ({preview}{suffix})"
        )
    return numeric_keys


def load_supplemental_patch(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}

    payload = json.loads(path.read_text(encoding="utf-8"))
    return {
        str(numeric).strip(): str(marked).strip()
        for numeric, marked in payload.items()
        if str(numeric).strip() and str(marked).strip()
    }


def numeric_to_marked_syllable(numeric_pinyin: str) -> str:
    if not numeric_pinyin or not numeric_pinyin[-1].isdigit():
        return numeric_pinyin

    tone = numeric_pinyin[-1]
    syllable = numeric_pinyin[:-1]
    if tone == "5":
        return syllable

    special_cases = {
        "ê": "ê",
        "m": "m",
        "n": "n",
        "ng": "ng",
        "hm": "hm",
        "hn": "hn",
        "hng": "hng",
    }
    if syllable in special_cases:
        base = special_cases[syllable]
        if syllable == "ng":
            return TONE_MARKS["n"][tone] + "g"
        if syllable == "hm":
            return "h" + TONE_MARKS["m"][tone]
        if syllable == "hn":
            return "h" + TONE_MARKS["n"][tone]
        if syllable == "hng":
            return "h" + TONE_MARKS["n"][tone] + "g"
        return TONE_MARKS[base][tone]

    tone_index: int | None = None
    for vowel in ("a", "o", "e"):
        if vowel in syllable:
            tone_index = syllable.index(vowel)
            break
    if tone_index is None and "iu" in syllable:
        tone_index = syllable.index("iu") + 1
    if tone_index is None and "ui" in syllable:
        tone_index = syllable.index("ui") + 1
    if tone_index is None:
        for vowel in ("i", "u", "ü"):
            if vowel in syllable:
                tone_index = syllable.index(vowel)
                break
    if tone_index is None:
        return syllable

    vowel = syllable[tone_index]
    marked_vowel = TONE_MARKS.get(vowel, {}).get(tone)
    if marked_vowel is None:
        return syllable
    return syllable[:tone_index] + marked_vowel + syllable[tone_index + 1:]


def build_export_mapping(
    numeric_to_marked: dict[str, set[str]],
    allowed_keys: list[str],
    supplemental_patch: dict[str, str],
) -> tuple[OrderedDict[str, str], list[str]]:
    conflicts = {
        numeric: sorted(marked_values)
        for numeric, marked_values in numeric_to_marked.items()
        if numeric in allowed_keys and len(marked_values) != 1
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

    export_mapping: OrderedDict[str, str] = OrderedDict()
    missing_keys: list[str] = []
    for numeric in allowed_keys:
        marked_values = numeric_to_marked.get(numeric)
        if marked_values:
            export_mapping[numeric] = next(iter(marked_values))
            continue
        supplemental_marked = supplemental_patch.get(numeric)
        if supplemental_marked:
            export_mapping[numeric] = supplemental_marked
            missing_keys.append(numeric)
            continue
        export_mapping[numeric] = numeric_to_marked_syllable(numeric)
        missing_keys.append(numeric)

    return export_mapping, missing_keys


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    output_path = Path(args.output)
    codebook_path = Path(args.codebook)
    supplemental_patch_path = Path(args.supplemental_patch)

    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")
    if not codebook_path.exists():
        raise FileNotFoundError(f"codebook file not found: {codebook_path}")

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

        numeric_to_marked = collect_numeric_to_marked_pairs(conn, args.inventory_table)
        inventory_keys = load_inventory_numeric_syllables(conn, args.inventory_table)
    finally:
        conn.close()

    codebook_keys = load_codebook_keys(codebook_path)
    supplemental_patch = load_supplemental_patch(supplemental_patch_path)
    if args.export_domain == "inventory":
        allowed_keys = sorted(set(inventory_keys) | set(supplemental_patch))
    else:
        allowed_keys = sorted(set(codebook_keys) | set(supplemental_patch))
    export_mapping, missing_keys = build_export_mapping(
        numeric_to_marked,
        allowed_keys,
        supplemental_patch,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(export_mapping, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"database: {db_path}")
    print(f"output: {output_path}")
    print(f"export_domain: {args.export_domain}")
    print(f"rows_exported: {len(export_mapping)}")
    print(f"inventory_keys: {len(inventory_keys)}")
    print(f"codebook_keys: {len(codebook_keys)}")
    print(f"supplemental_patch_keys: {len(supplemental_patch)}")
    inventory_numeric = set(inventory_keys)
    export_keys = set(export_mapping)
    print(
        f"inventory_not_exported: {len(inventory_numeric - export_keys)}"
    )
    print(
        f"export_beyond_codebook: {len(export_keys - set(codebook_keys))}"
    )
    print(f"source_only_keys_ignored: {len(set(numeric_to_marked) - export_keys)}")
    print(f"missing_keys_backfilled: {len(missing_keys)}")
    print(f"validation_errors: {validation_report['summary']['error_count']}")
    print(f"validation_warnings: {validation_report['summary']['warning_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
