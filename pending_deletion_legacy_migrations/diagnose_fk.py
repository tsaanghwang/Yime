from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    print("=== tables/triggers/indexes ===")
    for r in cur.execute("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE type IN ('table','trigger','index') ORDER BY type,name"):
        print(r)
    print("\n=== PRAGMA table_info('音元拼音') ===")
    for r in cur.execute("PRAGMA table_info('音元拼音')"): print(r)
    print("\n=== PRAGMA foreign_key_list('音元拼音') ===")
    for r in cur.execute("PRAGMA foreign_key_list('音元拼音')"): print(r)
    print("\n=== PRAGMA table_info('hanzi_phoneme_mapping') ===")
    for r in cur.execute("PRAGMA table_info('hanzi_phoneme_mapping')"): print(r)
print("\nDone.")
