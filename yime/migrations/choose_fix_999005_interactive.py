from pathlib import Path
import sqlite3, shutil, time, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
SAMPLE_ID = 999005
SAMPLE_CODE = "abbc"
BACKUP_SUFFIX = f".bak.{int(time.time())}"

def backup():
    bak = DB.with_suffix(DB.suffix + BACKUP_SUFFIX)
    shutil.copy(str(DB), str(bak))
    print("备份已创建:", bak)
    return bak

def show_state(cur):
    print("\n音元拼音 中相关行（映射 999005 / 999006 / 全拼匹配）:")
    for r in cur.execute('SELECT ROWID, 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" WHERE 映射编号 IN (999005,999006) OR 全拼=?', (SAMPLE_CODE,)):
        print(r)

def require(prompt):
    v = input(prompt + " 输入 YES 才继续: ").strip()
    if v != "YES":
        print("已取消")
        sys.exit(0)

def assign_mapping_if_safe(conn):
    cur = conn.cursor()
    # prefer updating a row that matches 全拼 or 干音 and has NULL 映射编号
    r = cur.execute('SELECT ROWID, 映射编号 FROM "音元拼音" WHERE (全拼=? OR 干音=?) LIMIT 1', (SAMPLE_CODE, SAMPLE_CODE)).fetchone()
    if r:
        rid, curmap = r[0], r[1]
        if curmap is None:
            cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE ROWID=?', (SAMPLE_ID, rid))
            conn.commit()
            print("已更新行 ROWID=", rid, " 映射编号 ->", SAMPLE_ID)
            return
        else:
            print("找到行但映射编号非空:", curmap, "未自动覆盖。")
            return
    print("未找到匹配行可更新。")

def insert_unique(conn):
    cur = conn.cursor()
    try:
        sys.path.insert(0, str(Path(__file__).parents[1]))
        from pinyin_importer import PinyinImporter
        vals = PinyinImporter()._generate_default_values(SAMPLE_CODE)
    except Exception:
        vals = {"全拼": SAMPLE_CODE, "简拼": SAMPLE_CODE, "首音": "", "干音": SAMPLE_CODE, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

    base = vals.get("简拼") or SAMPLE_CODE
    candidate = base
    i = 0
    import uuid, time, random
    while True:
        cnt = cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0]
        if cnt == 0:
            break
        i += 1
        if i <= 50:
            candidate = f"{base}_{i}"; continue
        # fallback to short uuid suffix
        candidate = f"{base}_{uuid.uuid4().hex[:8]}"
        if cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0] == 0:
            break
        time.sleep(0.05)

    vals["简拼"] = candidate
    cur.execute(
        'INSERT INTO "音元拼音" ("全拼","简拼","首音","干音","呼音","主音","末音","间音","韵音","映射编号") VALUES (?,?,?,?,?,?,?,?,?,?)',
        (
            vals.get("全拼"), vals.get("简拼"), vals.get("首音"), vals.get("干音"),
            vals.get("呼音"), vals.get("主音"), vals.get("末音"), vals.get("间音"),
            vals.get("韵音"), SAMPLE_ID
        ),
    )
    conn.commit()
    print("插入新行，简拼:", vals["简拼"], "受影响行数:", cur.rowcount)

def main():
    if not DB.exists():
        print("数据库未找到:", DB); return
    bak = backup()
    with sqlite3.connect(str(DB)) as conn:
        cur = conn.cursor()
        show_state(cur)
        print("\n选项：")
        print("1) 保留不变（退出）")
        print("2) 若存在匹配且映射编号为空则更新该行为 999005（安全更新）")
        print("3) 插入新的 音元拼音 行 并分配 映射编号=999005（会生成不冲突的 简拼）")
        choice = input("选择 1/2/3: ").strip()
        if choice == "1":
            print("退出，不做修改。"); return
        if choice == "2":
            require("准备执行安全更新")
            assign_mapping_if_safe(conn); return
        if choice == "3":
            require("准备插入新行")
            insert_unique(conn); return
        print("无效选择，退出。")

if __name__ == "__main__":
    main()
