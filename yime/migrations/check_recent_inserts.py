from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 检测表列，选择一个存在的时间戳列（若有）
    cols = [r["name"] for r in cur.execute("PRAGMA table_info(\"音元拼音\")").fetchall()]
    ts_candidates = ["创建时间", "created_at", "updated_at", "updated", "timestamp", "ctime"]
    ts_col = next((c for c in ts_candidates if c in cols), None)

    select_cols = ["ROWID", "编号", "映射编号", "全拼", "简拼"]
    if ts_col:
        select_cols.append(ts_col)

    print("查找表中 映射编号 非空 的最近 50 行：")
    q = f'SELECT {", ".join(select_cols)} FROM "音元拼音" WHERE 映射编号 IS NOT NULL ORDER BY ROWID DESC LIMIT 50'
    for row in cur.execute(q):
        print(dict(row))

    print("\n按 sample id 精确搜索（如 999001..999006）：")
    for mid in (999001,999002,999003,999004,999005,999006):
        r = cur.execute('SELECT ROWID, 编号, 映射编号, 全拼 FROM "音元拼音" WHERE 映射编号=? LIMIT 1', (mid,)).fetchone()
        print(mid, dict(r) if r else "NOT FOUND")

    print("\n也检查是否按 全拼/干音 插入了示例 code：")
    for code in ("abcd","abce","abcf","abbb","abbc","abcc"):
        r = cur.execute('SELECT COUNT(*) AS c FROM "音元拼音" WHERE 全拼=? OR 干音=?', (code, code)).fetchone()
        print(code, r["c"])
