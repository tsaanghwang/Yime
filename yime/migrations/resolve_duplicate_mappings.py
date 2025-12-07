from pathlib import Path
import sqlite3, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
TARGET_ROWID = 8  # 可改为你要更新的 ROWID 或使用 全拼 检测
TARGET_FULL = "abbc"
SET_ID = 999005
CUR_ID = 999006

if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    print("当前 映射编号=999005 的行：")
    for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 映射编号=?', (SET_ID,)).fetchall():
        print(dict(r))
    print("\n当前 映射编号=999006 的行：")
    for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 映射编号=?', (CUR_ID,)).fetchall():
        print(dict(r))

    # safety: ensure no existing row already uses SET_ID (unless user intends overwrite)
    exists_set = cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 映射编号=?', (SET_ID,)).fetchone()[0]
    if exists_set:
        print(f"\n发现已有 {exists_set} 行使用 映射编号={SET_ID}，不会自动覆盖。若要强制覆盖请手动执行 SQL。")
        sys.exit(0)

    # find candidate row by ROWID or 全拼
    row = cur.execute('SELECT ROWID, 全拼, 映射编号 FROM "音元拼音" WHERE ROWID=? OR 全拼=? LIMIT 1', (TARGET_ROWID, TARGET_FULL)).fetchone()
    if not row:
        print("\n未找到候选行（ROWID 或 全拼）。取消。"); sys.exit(1)

    # 使用位置访问以兼容不同环境的列名处理
    rid = row[0]
    full = row[1] if len(row) > 1 else None
    curmap = row[2] if len(row) > 2 else None

    print("\n候选行：", {"ROWID": rid, "全拼": full, "映射编号": curmap})
    confirm = input(f"将此行的 映射编号 从 {curmap} 修改为 {SET_ID}？输入 YES 以继续: ").strip()
    if confirm != "YES":
        print("已取消"); sys.exit(0)

    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (SET_ID, rid))
    conn.commit()
    print("已更新，受影响行数:", cur.rowcount)
