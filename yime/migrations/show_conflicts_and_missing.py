from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE = {
    999001: "abcd",
    999002: "abce",
    999003: "abcf",
    999004: "abbb",
    999005: "abbc",
    999006: "abcc",
}

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    print("检查按 映射编号 查到的行：")
    for mid, code in SAMPLE.items():
        r = cur.execute('SELECT ROWID, 映射编号, 全拼, 干音 FROM "音元拼音" WHERE 映射编号=?', (mid,)).fetchone()
        print(mid, "by 映射编号 ->", dict(r) if r else "NOT FOUND")
    print("\n检查按 全拼/干音 查到的行（可能引起 UNIQUE 冲突）：")
    for mid, code in SAMPLE.items():
        rows = cur.execute('SELECT ROWID, 映射编号, 全拼, 干音 FROM "音元拼音" WHERE 全拼=? OR 干音=?', (code, code)).fetchall()
        if rows:
            print(code, "matches:")
            for r in rows:
                print(" ", dict(r))
        else:
            print(code, "no match")
