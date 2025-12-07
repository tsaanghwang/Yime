from pathlib import Path
import sqlite3

DB = Path(__file__).parent / "pinyin_hanzi.db"

def run():
    with sqlite3.connect(str(DB)) as conn:
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        print("DB:", DB.resolve())
        print("PRAGMA integrity_check ->", cur.execute("PRAGMA integrity_check;").fetchone()[0])

        total = cur.execute('SELECT COUNT(*) AS c FROM "音元拼音";').fetchone()["c"]
        mapped = cur.execute('SELECT COUNT(*) AS c FROM "音元拼音" WHERE "映射编号" IS NOT NULL;').fetchone()["c"]
        null_jian = cur.execute('SELECT COUNT(*) AS c FROM "音元拼音" WHERE "简拼" IS NULL;').fetchone()["c"]
        print(f"音元拼音 总行数: {total}")
        print(f"已设置 映射编号 的行: {mapped} ({mapped/total:.1%} coverage)")
        print(f"简拼 为 NULL 的行: {null_jian}")

        print("\n前 20 条样例：")
        for row in cur.execute('SELECT 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" ORDER BY 编号 LIMIT 20;'):
            print(dict(row))

if __name__ == '__main__':
    run()
