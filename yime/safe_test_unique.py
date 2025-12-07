from pathlib import Path
import sqlite3

DB = Path(__file__).parent / "pinyin_hanzi.db"

def main():
    con = sqlite3.connect(str(DB))
    cur = con.cursor()
    try:
        cur.execute("SAVEPOINT t1")
        cur.execute('INSERT INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)', ("TMP_FULL_A","TMP_SH","G"))
        cur.execute('INSERT INTO "音元拼音"("全拼","简拼","干音") VALUES (?,?,?)', ("TMP_FULL_B","TMP_SH","G2"))
    except sqlite3.IntegrityError as e:
        print("约束触发，已回滚到保存点：", e)
        # 打印导致冲突的现有行，便于诊断
        try:
            cur.execute('SELECT "编号","全拼","简拼","干音" FROM "音元拼音" WHERE "简拼"=?', ("TMP_SH",))
            rows = cur.fetchall()
            print("冲突现有行数:", len(rows))
            for r in rows:
                print(r)
        except Exception as q_e:
            print("查询冲突行时出错:", q_e)
        cur.execute("ROLLBACK TO t1")
    except Exception as e:
        print("其他错误，已回滚：", e)
        cur.execute("ROLLBACK TO t1")
    finally:
        try:
            cur.execute("RELEASE t1")
        except Exception:
            pass
        con.close()
        print("完成（库未修改）")

if __name__ == "__main__":
    main()
