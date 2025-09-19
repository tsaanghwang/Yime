"""
检查并（可选）修正 音元拼音 表与 拼音映射关系 表 的映射编号一致性。
用法:
  python consolidate_mappings.py        -> 生成报告（dry-run）
  python consolidate_mappings.py --apply -> 在确认安全的情况下执行修正
"""
from pathlib import Path
import sqlite3
import csv
import sys

DB = Path(__file__).parent.resolve() / "pinyin_hanzi.db"
REPORT_DIR = Path(__file__).parent / "reports"
REPORT_DIR.mkdir(exist_ok=True)

def q(conn, sql, params=()):
    cur = conn.cursor()
    cur.execute(sql, params)
    return cur.fetchall()

def generate_reports(conn):
    # 基本信息
    total_audio = q(conn, 'SELECT COUNT(*) FROM "音元拼音"')[0][0]
    total_map = q(conn, 'SELECT COUNT(*) FROM "拼音映射关系"')[0][0]

    # 重复简拼检查（仅供参考）
    dup = q(conn, '''
        SELECT "简拼", COUNT(*) cnt FROM "音元拼音"
        WHERE "简拼" IS NOT NULL
        GROUP BY "简拼"
        HAVING cnt > 1
    ''')

    # 孤儿映射（音元拼音 指向不存在的 映射编号）
    orphan = q(conn, '''
        SELECT p."编号", p."全拼", p."映射编号"
        FROM "音元拼音" p
        LEFT JOIN "拼音映射关系" m ON p."映射编号" = m."映射编号"
        WHERE p."映射编号" IS NOT NULL AND m."映射编号" IS NULL
    ''')

    # 映射与全拼不匹配（映射行类型为 音元拼音）
    mismatch = q(conn, '''
        SELECT p."编号", p."全拼", p."映射编号", m."目标拼音"
        FROM "音元拼音" p
        JOIN "拼音映射关系" m ON p."映射编号" = m."映射编号"
        WHERE m."目标拼音类型" = '音元拼音' AND m."目标拼音" <> p."全拼"
    ''')

    # 找出没有映射编号但存在唯一匹配 mapping 的行（可安全填充）
    candidate = q(conn, '''
        SELECT p."编号", p."全拼",
               (SELECT m."映射编号" FROM "拼音映射关系" m
                 WHERE m."目标拼音类型"='音元拼音' AND m."目标拼音"=p."全拼"
                 LIMIT 2) AS maybe_map,
               (SELECT COUNT(*) FROM "拼音映射关系" m2
                 WHERE m2."目标拼音类型"='音元拼音' AND m2."目标拼音"=p."全拼") AS map_count
        FROM "音元拼音" p
        WHERE p."映射编号" IS NULL
    ''')

    # 写报告
    with open(REPORT_DIR / "summary.txt", "w", encoding="utf-8") as f:
        f.write(f"DB: {DB}\\n")
        f.write(f"音元拼音 总行: {total_audio}\\n")
        f.write(f"拼音映射关系 总行: {total_map}\\n")
        f.write(f"重复简拼组数: {len(dup)}\\n")
        f.write(f"孤儿映射数: {len(orphan)}\\n")
        f.write(f"映射不匹配数: {len(mismatch)}\\n")
        f.write(f"无映射但存在候选唯一匹配数: {len([r for r in candidate if r[3]==1])}\\n")

    def write_csv(name, rows, headers):
        if not rows:
            return
        with open(REPORT_DIR / name, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(headers)
            w.writerows(rows)

    write_csv("duplicate_shorthand.csv", dup, ["简拼", "count"])
    write_csv("orphan_mapping.csv", orphan, ["编号", "全拼", "映射编号"])
    write_csv("mapping_mismatch.csv", mismatch, ["编号", "全拼", "映射编号", "目标拼音"])
    write_csv("candidate_fill_map.csv", candidate, ["编号", "全拼", "maybe_map", "map_count"])

    print("报告已生成到 reports/ 目录。summary.txt 中有摘要。")

def apply_fixes(conn):
    # 将那些 map_count == 1 的音元拼音 的 映射编号 填上对应的唯一映射编号（可回滚）
    cur = conn.cursor()
    cur.execute('''
        SELECT p."编号", p."全拼",
               m."映射编号"
        FROM "音元拼音" p
        JOIN "拼音映射关系" m
          ON m."目标拼音类型"='音元拼音' AND m."目标拼音"=p."全拼"
        WHERE p."映射编号" IS NULL
        GROUP BY p."编号"
        HAVING COUNT(m."映射编号") = 1
    ''')
    to_fix = cur.fetchall()
    print(f"找到 {len(to_fix)} 条可安全填充的记录（将设置 映射编号）")
    if not to_fix:
        return 0
    for row in to_fix:
        pid, full, mid = row
        cur.execute('UPDATE "音元拼音" SET "映射编号"=? WHERE "编号"=?', (mid, pid))
    conn.commit()
    return len(to_fix)

def main():
    apply = "--apply" in sys.argv
    con = sqlite3.connect(str(DB))
    try:
        generate_reports(con)
        if apply:
            n = apply_fixes(con)
            print(f"已写入 {n} 条修正。")
        else:
            print("Dry-run 完成。若确认请用 --apply 执行修正。")
    finally:
        con.close()

if __name__ == "__main__":
    main()
