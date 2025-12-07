from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    r = cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='音元拼音'").fetchone()
    print("音元拼音 CREATE SQL:\n", r[0] if r else "音元拼音 table not found")
    print("\nPRAGMA table_info('音元拼音'):")
    for row in cur.execute("PRAGMA table_info('音元拼音')"):
        print(row)
    print("\nPRAGMA foreign_key_list('音元拼音'):")
    for row in cur.execute("PRAGMA foreign_key_list('音元拼音')"):
        print(row)
