from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_ID = 999005
CODE = "abbc"

def gen_defaults(code):
    try:
        sys.path.insert(0, str(Path(__file__).parents[1]))
        from pinyin_importer import PinyinImporter
        return PinyinImporter()._generate_default_values(code)
    except Exception:
        return {"全拼": code, "简拼": code, "首音": "", "干音": code, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # already present?
    if cur.execute('SELECT 1 FROM "音元拼音" WHERE 映射编号=? LIMIT 1', (SAMPLE_ID,)).fetchone():
        print("999005 already present, nothing to do.")
        sys.exit(0)

    # try find by 全拼 or 干音
    row = cur.execute('SELECT ROWID, 映射编号 FROM "音元拼音" WHERE 全拼=? OR 干音=? LIMIT 1', (CODE, CODE)).fetchone()
    if row:
        # use positional access to avoid KeyError when column key isn't present
        rid = row[0]
        current_mapping = row[1]
        if current_mapping is None:
            cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (SAMPLE_ID, rid))
            conn.commit()
            print("Updated existing row ROWID=", rid, "-> 映射编号=", SAMPLE_ID)
            sys.exit(0)
        else:
            print("Found row ROWID=", rid, "but 映射编号 is", current_mapping, "— not changed.")
            sys.exit(1)

    # insert new unique row (avoid 简拼 conflict)
    vals = gen_defaults(CODE)
    base = vals.get("简拼") or CODE
    candidate = base
    i = 0
    while cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0]:
        i += 1
        candidate = f"{base}_{i}"
        if i > 50:
            raise RuntimeError("无法生成非冲突的 简拼")
    vals["简拼"] = candidate

    cur.execute(
        'INSERT INTO "音元拼音" ("全拼","简拼","首音","干音","呼音","主音","末音","间音","韵音","映射编号") VALUES (?,?,?,?,?,?,?,?,?,?)',
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
    print("Inserted new row with 简拼=", vals["简拼"], "映射编号=", SAMPLE_ID)
