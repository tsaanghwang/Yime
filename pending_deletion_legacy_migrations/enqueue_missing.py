from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    # 插入尚未映射且还没入队的行
    cur.execute("""
    INSERT INTO mapping_queue(target_table, target_pk, hanzi, phoneme_key)
    SELECT '音元拼音', p.编号, p.全拼, p.干音
    FROM "音元拼音" p
    WHERE (p.映射编号 IS NULL OR p.映射编号 = 0)
      AND NOT EXISTS (
        SELECT 1 FROM mapping_queue q WHERE q.target_table='音元拼音' AND q.target_pk = p.编号 AND q.status = 'pending'
      )
    """)
    conn.commit()
    print("Enqueued rows:", cur.rowcount)
