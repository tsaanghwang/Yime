from pathlib import Path
import sqlite3, shutil, time, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
TMP_ID = -999999
A = 999005
B = 999006
CODE_A = "abbc"  # 999005 target code
CODE_B = "abcc"  # 999006 target code

def backup_db():
    bak = DB.with_suffix(f".bak.{int(time.time())}")
    shutil.copy(str(DB), str(bak))
    print("备份已创建:", bak)
    return bak

def show_state(cur):
    print("\n现有 音元拼音 相关行：")
    for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 映射编号 IN (?,?,?) OR 全拼 IN (?,?)',
                         (A, B, TMP_ID, CODE_A, CODE_B)).fetchall():
        print(dict(zip([c[0] for c in cur.description], r)))
    print("\n拼音映射关系 中相关条目：")
    for r in cur.execute('SELECT * FROM "拼音映射关系" WHERE 映射编号 IN (?,?)', (A, B)).fetchall():
        print(r)

def require(msg):
    v = input(msg + " 输入 YES 才继续: ").strip()
    if v != "YES":
        print("已取消")
        sys.exit(0)

def single_update(conn):
    cur = conn.cursor()
    # 仅当全拼为 CODE_B 且 当前映射为 A 时安全更新；否则需强制
    cur.execute('SELECT ROWID, 映射编号 FROM "音元拼音" WHERE 全拼=? LIMIT 1', (CODE_B,))
    r = cur.fetchone()
    if not r:
        print("未找到 全拼=", CODE_B, "的行，无法单边更新。")
        return
    if r[1] == B:
        print("该行已为目标映射编号", B)
        return
    if r[1] != A:
        print(f"该行当前映射编号为 {r[1]}（非 {A}）。若确定覆盖请在后续提示中输入 FORCE。")
        v = input("输入 FORCE 以覆盖，或留空取消: ").strip()
        if v != "FORCE":
            print("已取消")
            return
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (B, r[0]))
    conn.commit()
    print("更新完成，受影响行数:", cur.rowcount)

def swap_mappings(conn):
    cur = conn.cursor()
    # 使用 TMP_ID 做三步交换
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 映射编号=?', (TMP_ID, A))
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 映射编号=?', (A, B))
    cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 映射编号=?', (B, TMP_ID))
    conn.commit()
    print("交换完成，变更计数:", conn.total_changes)

def insert_unique_abbc(conn):
    cur = conn.cursor()
    # 尝试从导入器生成默认字段
    try:
        sys.path.insert(0, str(Path(__file__).parents[1]))
        from pinyin_importer import PinyinImporter
        p = PinyinImporter()
        vals = p._generate_default_values(CODE_A)
    except Exception:
        vals = {"全拼": CODE_A, "简拼": CODE_A, "首音": "", "干音": CODE_A, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

    base = vals.get("简拼") or CODE_A
    cand = base
    i = 0
    while cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (cand, vals.get("全拼"))).fetchone()[0]:
        i += 1
        cand = f"{base}_{i}"
        if i > 50:
            raise RuntimeError("无法生成非冲突的 简拼")
    vals["简拼"] = cand
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
            A,
        ),
    )
    conn.commit()
    print("插入新行，简拼:", vals["简拼"], "受影响行数:", cur.rowcount)

def main():
    if not DB.exists():
        print("数据库未找到:", DB); return
    print("将对数据库执行修改。建议先备份。")
    bak = backup_db()
    with sqlite3.connect(str(DB)) as conn:
        cur = conn.cursor()
        show_state(cur)
        print("\n选项：")
        print("1) 保留不变（退出）")
        print("2) 单边更新：将 全拼='abcc' 的行置为 映射编号=999006（仅在当前为999005或强制时覆盖）")
        print("3) 交换映射：把 999005 和 999006 对调（使用临时 id 避免冲突）")
        print("4) 插入新行：为 abbc 插入新行并分配 映射编号=999005（会尝试生成不冲突的 简拼）")
        choice = input("选择 1/2/3/4: ").strip()
        if choice == "1":
            print("不做修改，退出。")
            return
        if choice == "2":
            require("你即将进行单边更新")
            single_update(conn)
            return
        if choice == "3":
            require("你即将交换两个映射编号（会修改多行）")
            swap_mappings(conn)
            return
        if choice == "4":
            require("你即将插入新行并分配映射编号")
            insert_unique_abbc(conn)
            return
        print("无效选择，退出。")

if __name__ == "__main__":
    main()
