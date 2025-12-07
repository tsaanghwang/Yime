from pathlib import Path
import sqlite3
import sys

MIGRATIONS_DIR = Path(__file__).parent
DB = MIGRATIONS_DIR.parent / "pinyin_hanzi.db"
SQL_PATH = MIGRATIONS_DIR / "000_create_mapping_queue.sql"

if not SQL_PATH.exists():
    print(f"SQL file not found: {SQL_PATH}", file=sys.stderr)
    sys.exit(2)

if not DB.exists():
    print(f"Database not found: {DB}", file=sys.stderr)
    sys.exit(3)

try:
    sql = SQL_PATH.read_text(encoding="utf-8")
    with sqlite3.connect(str(DB)) as conn:
        conn.executescript(sql)
    print("applied")
    sys.exit(0)
except Exception as e:
    print("Error applying migration:", e, file=sys.stderr)
    sys.exit(1)
