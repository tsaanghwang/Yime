from pathlib import Path
import sqlite3
DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    for mid in (999001, 999002, 999003, 999004, 999005, 999006):
        row = cur.execute('SELECT 编号, 全拼, 简拼, 干音, 首音, 呼音, 主音, 末音, 间音, 韵音 FROM "音元拼音" WHERE 映射编号=?', (mid,)).fetchone()
        print(mid, dict(row) if row else "NOT FOUND")
