from pathlib import Path
import sqlite3, sys, time

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_IDS = (999001, 999002, 999003, 999004, 999005, 999006)

if not DB.exists():
    print("数据库不存在:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()

    # 确认表存在
    tbl = cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='拼音映射关系'").fetchone()
    if not tbl:
        print("表 '拼音映射关系' 不存在。请先确认表名是否正确。")
        sys.exit(2)

    cols = cur.execute("PRAGMA table_info('拼音映射关系')").fetchall()
    # cols rows: (cid, name, type, notnull, dflt_value, pk)
    col_names = [c[1] for c in cols]
    print("拼音映射关系 列:", col_names)

    key_col = "映射编号" if "映射编号" in col_names else None
    if not key_col:
        print("未发现 映射编号 列，表结构可能不匹配。请贴出 PRAGMA table_info 输出以便进一步处理。")
        sys.exit(3)

    # 找出必须提供的列（NOT NULL 且无默认，除去主键列）
    required = []
    for cid, name, typ, notnull, dflt, pk in cols:
        if name == key_col:
            continue
        if pk:
            continue
        if notnull and dflt is None:
            required.append((name, typ))
    print("需填充的必填列:", required)

    # 构造插入列和默认值（按类型猜测）
    def default_for(typ):
        t = (typ or "").upper()
        if "INT" in t:
            return 0
        if "CHAR" in t or "CLOB" in t or "TEXT" in t:
            return ""
        if "REAL" in t or "FLOA" in t or "DOUB" in t:
            return 0.0
        if "TIMESTAMP" in t or "DATE" in t:
            return time.strftime("%Y-%m-%d %H:%M:%S")
        return ""

    insert_cols = [key_col] + [c for c, _ in required]
    placeholders = "(" + ",".join("?" for _ in insert_cols) + ")"
    sql = f'INSERT OR IGNORE INTO "拼音映射关系" ({",".join(insert_cols)}) VALUES {placeholders}'
    print("Prepared SQL:", sql)

    inserted = 0
    for mid in SAMPLE_IDS:
        vals = [mid]
        for name, typ in required:
            vals.append(default_for(typ))
        try:
            cur.execute(sql, vals)
            if cur.rowcount:
                inserted += 1
        except Exception as e:
            print("插入占位映射失败:", mid, e)
    conn.commit()
    print("占位映射处理完成，新增/忽略:", inserted)
