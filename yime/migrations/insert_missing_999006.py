from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_ID = 999006
CODE = "abcc"

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 若已有行但映射编号为空则更新
    r = cur.execute('SELECT ROWID, 映射编号 FROM "音元拼音" WHERE 全拼=? OR 干音=? LIMIT 1', (CODE, CODE)).fetchone()
    if r:
        if r["映射编号"] is None:
            cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (SAMPLE_ID, r["ROWID"]))
            conn.commit()
            print("Updated 映射编号 on existing row:", r["ROWID"])
        else:
            print("Row exists with 映射编号, skipped:", r["映射编号"])
        sys.exit(0)

    # 否则尝试用导入器生成默认字段并插入
    try:
        sys.path.insert(0, str(Path(__file__).parents[1]))
        from pinyin_importer import PinyinImporter
        p = PinyinImporter()
        vals = p._generate_default_values(CODE)
    except Exception:
        vals = {"全拼": CODE, "简拼": CODE, "首音": "", "干音": CODE, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

    cur.execute(
        'INSERT OR IGNORE INTO "音元拼音" ("全拼","简拼","首音","干音","呼音","主音","末音","间音","韵音","映射编号") VALUES (?,?,?,?,?,?,?,?,?,?)',
        (
            vals.get("全拼"),
            vals.get("简拼"),
            vals.get("首音"),
            vals.get("干音"),
            vals.get("呼音"),
            vals.get("主音"),
            vals.get("末音"),
            vals.get("间音"),
            vals.get("韵音"),
            SAMPLE_ID,
        ),
    )
    conn.commit()
    print("Inserted row (if not ignored). rowcount:", cur.rowcount)
