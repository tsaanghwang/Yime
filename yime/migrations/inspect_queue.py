from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cnt = cur.execute("SELECT COUNT(*) AS c FROM mapping_queue").fetchone()["c"]
    print("mapping_queue count:", cnt)
    for row in cur.execute("SELECT * FROM mapping_queue ORDER BY created_at DESC LIMIT 10"):
        print(dict(row))
