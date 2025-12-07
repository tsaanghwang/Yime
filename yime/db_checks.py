from pathlib import Path
import sqlite3
import sys

DB = Path(__file__).parent / "pinyin_hanzi.db"
if not DB.exists():
    print("数据库不存在:", DB)
    sys.exit(1)

def q(cur, sql):
    cur.execute(sql)
    return cur.fetchall()

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    print("DB:", DB.resolve())
    print("PRAGMA integrity_check ->", q(cur, "PRAGMA integrity_check;"))

    # 总行数
    total = q(cur, "SELECT COUNT(*) AS c FROM \"音元拼音\";")
    print("音元拼音 总行数:", total[0]["c"] if total else "N/A")

    # 重复简拼
    dup = q(cur, "SELECT 简拼, COUNT(*) AS cnt FROM \"音元拼音\" WHERE 简拼 IS NOT NULL GROUP BY 简拼 HAVING COUNT(*)>1;")
    print("重复简拼数:", len(dup))
    for row in dup:
        print(dict(row))

    # 孤儿映射
    orphan = q(cur, "SELECT p.编号,p.全拼,p.映射编号 FROM \"音元拼音\" p LEFT JOIN \"拼音映射关系\" m ON p.映射编号 = m.映射编号 WHERE p.映射编号 IS NOT NULL AND m.映射编号 IS NULL;")
    print("孤儿映射数:", len(orphan))
    for row in orphan[:20]:
        print(dict(row))
