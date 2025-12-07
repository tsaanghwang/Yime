from pathlib import Path
import sqlite3, sys
ROOT = Path(__file__).parents[1]
DB = ROOT / "pinyin_hanzi.db"
CODE = "abbc"
SAMPLE_ID = 999005

# 如果项目有导入器用于生成字段，可复用；否则用 minimal defaults
try:
    sys.path.insert(0, str(ROOT))
    from pinyin_importer import PinyinImporter
    p = PinyinImporter()
    vals = p._generate_default_values(CODE)
except Exception:
    vals = {"全拼": CODE, "简拼": CODE, "首音": "", "干音": CODE, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    base = vals.get("简拼", CODE) or CODE
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
    print("inserted new row with 简拼:", vals["简拼"], "rowcount:", cur.rowcount)
