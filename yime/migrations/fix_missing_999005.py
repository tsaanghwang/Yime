from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_ID = 999005
CODE = "abbc"

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    # 1) 尝试按 全拼 更新（仅当 映射编号 为空时）
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 全拼=? AND (映射编号 IS NULL OR 映射编号="")', (SAMPLE_ID, CODE))
    if cur.rowcount:
        print("Updated 映射编号 on existing row(s):", cur.rowcount)
        conn.commit()
        sys.exit(0)

    # 2) 再尝试按 干音 更新（防止全拼/干音 不一致）
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 干音=? AND (映射编号 IS NULL OR 映射编号="")', (SAMPLE_ID, CODE))
    if cur.rowcount:
        print("Updated 映射编号 by 干音 on row(s):", cur.rowcount)
        conn.commit()
        sys.exit(0)

    # 3) 若未找到，插入新记录（使用导入器生成默认字段）
    sys.path.insert(0, str(Path(__file__).parents[1]))
    try:
        from pinyin_importer import PinyinImporter
    except Exception as e:
        print("无法导入 pinyin_importer:", e)
        sys.exit(2)

    p = PinyinImporter()
    vals = p._generate_default_values(CODE)
    insert_vals = (
        vals.get("全拼",""),
        vals.get("简拼",""),
        vals.get("首音",""),
        vals.get("干音",""),
        vals.get("呼音",""),
        vals.get("主音",""),
        vals.get("末音",""),
        vals.get("间音",""),
        vals.get("韵音",""),
        SAMPLE_ID,
    )
    cur.execute(
        'INSERT OR IGNORE INTO "音元拼音" ("全拼","简拼","首音","干音","呼音","主音","末音","间音","韵音","映射编号") VALUES (?,?,?,?,?,?,?,?,?,?)',
        insert_vals,
    )
    if cur.rowcount:
        print("Inserted missing sample with 映射编号:", SAMPLE_ID)
    else:
        print("Insert ignored (可能存在 UNIQUE 冲突)。")
    conn.commit()
