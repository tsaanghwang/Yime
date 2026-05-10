from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_IDS = (999001, 999002, 999003, 999004, 999005, 999006)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()

    # 检测可用的“标记来源”列名
    cols = [r[1] for r in cur.execute("PRAGMA table_info('拼音映射关系')").fetchall()]
    candidate_source_cols = ["source", "备注", "note", "来源", "remark"]
    source_col = next((c for c in candidate_source_cols if c in cols), None)

    if source_col:
        placeholders = [r[0] for r in cur.execute(f'SELECT 映射编号 FROM "拼音映射关系" WHERE {source_col}=?', ("placeholder",)).fetchall()]
        print("Using source column:", source_col, "found placeholders:", placeholders)
    else:
        # 回退：把我们关心的 sample ids 视为占位（存在即为占位候选）
        existing = [r[0] for r in cur.execute('SELECT 映射编号 FROM "拼音映射关系" WHERE 映射编号 IN ({})'.format(",".join("?" for _ in SAMPLE_IDS)), SAMPLE_IDS).fetchall()]
        placeholders = existing
        print("No source-like column found; treating existing sample IDs as placeholder candidates:", placeholders)

    if not placeholders:
        print("没有占位映射可处理。")
    else:
        # 找出被音元拼音引用的映射编号
        used_rows = cur.execute('SELECT DISTINCT 映射编号 FROM "音元拼音" WHERE 映射编号 IS NOT NULL').fetchall()
        used = {r[0] for r in used_rows if r[0] is not None}
        to_delete = [mid for mid in placeholders if mid not in used]
        if not to_delete:
            print("所有占位映射仍被引用或无可删除项。")
        else:
            q = 'DELETE FROM "拼音映射关系" WHERE 映射编号 IN ({})'.format(",".join("?" for _ in to_delete))
            cur.execute(q, to_delete)
            conn.commit()
            print("已删除占位映射:", to_delete)
