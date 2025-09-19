from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    print("=== 音元拼音 table SQL ===")
    r = cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='音元拼音'").fetchone()
    print(r[0] if r else "音元拼音 table not found")
    print("\n=== PRAGMA table_info('音元拼音') ===")
    for row in cur.execute("PRAGMA table_info('音元拼音')"):
        print(row)
    print("\n=== PRAGMA foreign_key_list('音元拼音') ===")
    for row in cur.execute("PRAGMA foreign_key_list('音元拼音')"):
        print(row)
    print("\n=== hanzi_phoneme_mapping table info ===")
    for row in cur.execute("PRAGMA table_info('hanzi_phoneme_mapping')"):
        print(row)
