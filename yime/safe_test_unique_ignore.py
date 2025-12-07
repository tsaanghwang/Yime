from pathlib import Path
import sqlite3

DB = Path(__file__).parent / "pinyin_hanzi.db"

def main():
    con = sqlite3.connect(str(DB))
    cur = con.cursor()
    cur.execute("PRAGMA foreign_keys = ON;")
    cur.execute("PRAGMA index_list('音元拼音');")
    print("index_list:", cur.fetchall())

    # 用 INSERT OR IGNORE 做无异常测试，然后回滚以保证库不变
    try:
        cur.execute("BEGIN")
        cur.execute(
            'INSERT OR IGNORE INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)',
            ("TMP_FULL_A", "TMP_SH", "G")
        )
        cur.execute(
            'INSERT OR IGNORE INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)',
            ("TMP_FULL_B", "TMP_SH", "G2")
        )
        # 不提交，回滚以确保测试不改变数据库
        con.rollback()
        print("测试完成（INSERT OR IGNORE，已回滚）")
    finally:
        con.close()

if __name__ == "__main__":
    main()
