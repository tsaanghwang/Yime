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

    missing = []
    print("逐条检查映射编号与可能的冲突：")
    for mid, code in SAMPLE.items():
        row = cur.execute('SELECT ROWID, 映射编号, 全拼, 干音 FROM "音元拼音" WHERE 映射编号=?', (mid,)).fetchone()
        if row:
            print(f"{mid} -> FOUND (映射编号):", dict(row))
            continue
        # not found by 映射编号 — check by 全拼 / 干音
        by_full = cur.execute('SELECT ROWID, 映射编号, 全拼, 干音 FROM "音元拼音" WHERE 全拼=?', (code,)).fetchall()
        by_gan = cur.execute('SELECT ROWID, 映射编号, 全拼, 干音 FROM "音元拼音" WHERE 干音=?', (code,)).fetchall()
        if by_full or by_gan:
            print(f"{mid} -> NOT FOUND by 映射编号, but matching rows exist for code='{code}':")
            for r in by_full + by_gan:
                print("  MATCH:", dict(r))
        else:
            print(f"{mid} -> NOT FOUND and no rows with 全拼/干音='{code}'")
            missing.append(mid)

    print("\nSummary: missing 映射编号 rows:", missing)
    # also print counts of 全拼 occurrences for sample codes
    print("\nCounts by 全拼:")
    for code in SAMPLE.values():
        c = cur.execute('SELECT COUNT(*) AS c FROM "音元拼音" WHERE 全拼=?', (code,)).fetchone()["c"]
        print(code, c)
