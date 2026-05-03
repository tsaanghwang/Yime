from pathlib import Path
import sqlite3

DB = Path(__file__).resolve().parent.parent / "pinyin_hanzi.db"

def main(dry_run=True):
    con = sqlite3.connect(str(DB))
    cur = con.cursor()
    cur.execute('SELECT "编号","全拼","简拼","干音" FROM "音元拼音" WHERE "全拼" LIKE ? OR "简拼" = ?', ('TMP_FULL_%','TMP_SH'))
    rows = cur.fetchall()
    print("找到行数:", len(rows))
    for r in rows:
        print(r)
    if rows and not dry_run:
        cur.execute('DELETE FROM "音元拼音" WHERE "全拼" LIKE ? OR "简拼" = ?', ('TMP_FULL_%','TMP_SH'))
        con.commit()
        print("已删除测试行")
    con.close()

if __name__ == "__main__":
    main(dry_run=True)  # 改成 dry_run=False 执行删除
