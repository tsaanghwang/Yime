from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


DEFAULT_TABLE = "m_distinct_syllable_inventory"


def export_inventory(
    source_database: Path,
    output_path: Path,
    *,
    table_name: str = DEFAULT_TABLE,
) -> int:
    if table_name != DEFAULT_TABLE:
        raise ValueError(f"unsupported materialized inventory table: {table_name}")

    database_uri = source_database.resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(database_uri, uri=True) as connection:
        rows = [
            str(row[0]).strip()
            for row in connection.execute(
                f"SELECT numeric_syllable FROM {DEFAULT_TABLE} "
                "ORDER BY numeric_syllable"
            )
            if str(row[0]).strip()
        ]

    if len(rows) != len(set(rows)):
        raise ValueError("materialized numeric syllable inventory contains duplicates")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        "pinyin_tone\n" + "\n".join(rows) + "\n",
        encoding="utf-8",
    )
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export the source-attested materialized syllable inventory as TSV."
    )
    parser.add_argument("--source-db", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    count = export_inventory(args.source_db, args.output)
    print(f"materialized syllable inventory: {count} rows")
    print(f"output: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
