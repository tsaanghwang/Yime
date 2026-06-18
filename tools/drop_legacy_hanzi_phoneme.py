"""Drop legacy hanzi↔phoneme experiment objects from ``pinyin_hanzi.db``.

Early IME prototyping added tables when encoding↔hanzi mapping was still unresolved.
None of these objects are referenced by the current rebuild/runtime chain.

Removed objects:

- ``hanzi_phoneme`` + ``homophone_view`` + ``idx_pinyin``
- ``hanzi_phoneme_mapping`` + ``idx_hanzi_phoneme``
- ``mapping_queue`` (pending rows targeting old 音元拼音-style tables)

Safe to run repeatedly (``IF EXISTS``).
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

DEFAULT_DB_PATH = Path(__file__).resolve().parents[1] / "yime" / "pinyin_hanzi.db"

# Order: views → indexes → tables (queue before mapping if ever FK-linked; currently none)
_DROP_STATEMENTS = (
    "DROP VIEW IF EXISTS homophone_view",
    "DROP INDEX IF EXISTS idx_pinyin",
    "DROP INDEX IF EXISTS idx_hanzi_phoneme",
    "DROP TABLE IF EXISTS hanzi_phoneme",
    "DROP TABLE IF EXISTS mapping_queue",
    "DROP TABLE IF EXISTS hanzi_phoneme_mapping",
)


def drop_legacy_hanzi_phoneme_experiment(conn: sqlite3.Connection) -> list[str]:
    dropped: list[str] = []
    cur = conn.cursor()
    for statement in _DROP_STATEMENTS:
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
        dropped = drop_legacy_hanzi_phoneme_experiment(conn)
    finally:
        conn.close()

    print(f"Cleaned legacy hanzi_phoneme experiment objects in {db_path}:")
    for statement in dropped:
        print(f"  {statement}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Backward-compatible alias for prior script name
drop_legacy_hanzi_phoneme = drop_legacy_hanzi_phoneme_experiment
