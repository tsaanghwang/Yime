"""Drop legacy Chinese pinyin schema tables from ``pinyin_hanzi.db``.

Removed tables (replaced by mainline English tables):

- ``数字标调拼音`` → ``numeric_pinyin_inventory``
- ``多式拼音映射关系`` → ``pinyin_yime_code`` (+ ``mapping_yime_code`` for legacy ids)
- ``音元拼音`` → ``yinjie_slot_decomposition`` (+ ``pinyin_yime_code``)

No runtime / IME code reads these tables. Safe to run repeatedly.
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

DEFAULT_DB_PATH = Path(__file__).resolve().parents[1] / "yime" / "pinyin_hanzi.db"

_LEGACY_TABLES = (
    "音元拼音",
    "数字标调拼音",
    "多式拼音映射关系",
)


def drop_legacy_chinese_pinyin_tables(conn: sqlite3.Connection) -> list[str]:
    dropped: list[str] = []
    cur = conn.cursor()
    # Child tables first (legacy FK order).
    for table_name in _LEGACY_TABLES:
        statement = f'DROP TABLE IF EXISTS "{table_name}"'
        cur.execute(statement)
        dropped.append(statement)
    conn.commit()
    return dropped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB_PATH,
        help=f"Target SQLite database (default: {DEFAULT_DB_PATH})",
    )
    args = parser.parse_args()
    db_path = args.db.resolve()
    if not db_path.exists():
        raise SystemExit(f"Database not found: {db_path}")

    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA foreign_keys = OFF")
        dropped = drop_legacy_chinese_pinyin_tables(conn)
    finally:
        conn.close()

    print(f"Cleaned legacy Chinese pinyin tables in {db_path}:")
    for statement in dropped:
        print(f"  {statement}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
