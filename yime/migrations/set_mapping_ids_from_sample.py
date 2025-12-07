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
    cur = conn.cursor()
    updated = 0
    for mid, code in SAMPLE.items():
        # 仅在映射编号为空或 NULL 时更新，避免覆盖已有映射
        cur.execute('SELECT 映射编号, ROWID FROM "音元拼音" WHERE 全拼=? LIMIT 1', (code,))
        r = cur.fetchone()
        if not r:
            print(f"{mid} ({code}) -> no row with 全拼")
            continue
        current = r[0]
        if current is None:
            cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (mid, r[1]))
            updated += cur.rowcount
            print(f"{mid} ({code}) -> updated 映射编号 (ROWID={r[1]})")
        else:
            print(f"{mid} ({code}) -> skipped (already 映射编号={current})")
    conn.commit()
    print("总更新条数:", updated)
