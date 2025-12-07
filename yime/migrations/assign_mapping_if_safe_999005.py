from pathlib import Path
import sqlite3, sys
ROOT = Path(__file__).parents[1]
DB = ROOT / "pinyin_hanzi.db"
SAMPLE_ID = 999005
CODE = "abbc"

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    # find candidate rows
    row = cur.execute('SELECT ROWID, 映射编号, 全拼, 简拼, 干音 FROM "音元拼音" WHERE 全拼=? OR 干音=? LIMIT 1', (CODE, CODE)).fetchone()
    if not row:
        print("未找到候选行，需插入新行或再次运行插入脚本。")
        sys.exit(0)
    print("Found candidate:", row)
    if row[1] is None:
        cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (SAMPLE_ID, row[0]))
        conn.commit()
        print("已安全更新 映射编号 ->", SAMPLE_ID)
    elif row[1] == SAMPLE_ID:
        print("行已含目标 映射编号，未作修改。")
    else:
        print("警告: 行已有不同 映射编号:", row[1], "未自动覆盖。请人工确认。")
