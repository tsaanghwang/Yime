from pathlib import Path
import sqlite3

db = Path(__file__).parent / "pinyin_hanzi.db"
con = sqlite3.connect(str(db))
cur = con.cursor()

# 列出音元拼音表的索引
cur.execute("PRAGMA index_list('音元拼音');")
print("index_list:", cur.fetchall())

# 尝试插入模拟重复（在事务中测试，出错会回滚）
try:
    cur.execute("BEGIN")
    cur.execute(
        'INSERT INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)',
        ("TEST_FULL_A", "SAME_SH", "G")
    )
    cur.execute(
        'INSERT INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)',
        ("TEST_FULL_B", "SAME_SH", "G2")
    )
    con.commit()
    print("插入成功（未触发唯一约束）")
except sqlite3.IntegrityError as e:
    print("约束触发:", e)
    con.rollback()
finally:
    con.close()
