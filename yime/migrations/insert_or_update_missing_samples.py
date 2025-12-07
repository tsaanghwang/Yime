from pathlib import Path
import sys, sqlite3

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT))

from pinyin_importer import PinyinImporter

DB = ROOT / "pinyin_hanzi.db"
SAMPLE = {
    999001: "abcd",
    999002: "abce",
    999003: "abcf",
    999004: "abbb",
    999005: "abbc",
    999006: "abcc",
}

p = PinyinImporter()

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    inserted = 0
    updated = 0
    for mid, code in SAMPLE.items():
        row = cur.execute('SELECT ROWID, 映射编号 FROM "音元拼音" WHERE 全拼=? OR 干音=? LIMIT 1', (code, code)).fetchone()
        if row:
            if row["映射编号"] is None:
                cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (mid, row["ROWID"]))
                updated += cur.rowcount
                print(f"{mid} ({code}) -> updated 映射编号 on ROWID={row['ROWID']}")
            else:
                print(f"{mid} ({code}) -> exists with 映射编号={row['映射编号']}, skipped")
            continue

        # not found: create defaults and insert
        cols = p._generate_default_values(code)
        vals = (
            cols.get("全拼", ""),
            cols.get("简拼", ""),
            cols.get("首音", ""),
            cols.get("干音", ""),
            cols.get("呼音", ""),
            cols.get("主音", ""),
            cols.get("末音", ""),
            cols.get("间音", ""),
            cols.get("韵音", ""),
            mid,
        )
        cur.execute(
            'INSERT OR IGNORE INTO "音元拼音" ("全拼","简拼","首音","干音","呼音","主音","末音","间音","韵音","映射编号") VALUES (?,?,?,?,?,?,?,?,?,?)',
            vals,
        )
        if cur.rowcount:
            inserted += 1
            print(f"{mid} ({code}) -> inserted")
        else:
            print(f"{mid} ({code}) -> insert ignored (possible UNIQUE conflict)")

    conn.commit()
    print("结果：插入", inserted, "条，更新", updated, "条")
