from pathlib import Path
import sqlite3
import sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"

if not DB.exists():
    print("数据库不存在:", DB)
    sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    before = cur.execute(
        "SELECT COUNT(*) FROM mapping_queue WHERE target_table='音元拼音' AND status='pending'"
    ).fetchone()[0]
    cur.execute("""
    INSERT INTO mapping_queue(target_table, target_pk, hanzi, phoneme_key)
    SELECT '音元拼音', p.编号, p.全拼, p.干音
    FROM "音元拼音" p
    WHERE NOT EXISTS (
      SELECT 1 FROM mapping_queue q
      WHERE q.target_table='音元拼音' AND q.target_pk = p.编号 AND q.status = 'pending'
    )
    """)
    conn.commit()
    after = cur.execute(
        "SELECT COUNT(*) FROM mapping_queue WHERE target_table='音元拼音' AND status='pending'"
    ).fetchone()[0]
    print("Enqueued rows (attempt):", after - before)
