from pathlib import Path
import sqlite3, sys
ROOT = Path(__file__).parents[1]
DB = ROOT / "pinyin_hanzi.db"
SAMPLE_ID = 999005
CODE = "abbc"

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    # try to get generated simple fields via importer (if available)
    try:
        sys.path.insert(0, str(ROOT))
        from pinyin_importer import PinyinImporter
        p = PinyinImporter()
        vals = p._generate_default_values(CODE)
        jinpin = vals.get("简拼", "")
    except Exception:
        jinpin = None

    print("查找与 全拼/简拼/干音 冲突的行（code =", CODE, "）:")
    for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 全拼=? OR 干音=?' + ('' if jinpin is None else ' OR 简拼=?'), (CODE, CODE) + (() if jinpin is None else (jinpin,))):
        print(dict(r))

    # also exact match by 简拼 if available
    if jinpin:
        print("\n推测的 简拼:", jinpin)
        for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 简拼=?', (jinpin,)):
            print("简拼匹配:", dict(r))
