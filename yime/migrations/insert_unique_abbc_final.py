from pathlib import Path
import sqlite3, sys
ROOT = Path(__file__).parents[1]
DB = ROOT / "pinyin_hanzi.db"
CODE = "abbc"
SAMPLE_ID = 999005

def gen_defaults(code):
    try:
        sys.path.insert(0, str(ROOT))
        from pinyin_importer import PinyinImporter
        return PinyinImporter()._generate_default_values(code)
    except Exception:
        return {"全拼": code, "简拼": code, "首音": "", "干音": code, "呼音": "", "主音": "", "末音": "", "间音": "", "韵音": ""}

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    vals = gen_defaults(CODE)
    base = vals.get("简拼") or CODE
    candidate = base
    i = 0
    import time, random, uuid

    # 先用递增后缀尝试若干次，再退回到时间戳/随机/UUID 后缀以保证能生成唯一值
    while True:
        cnt = cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0]
        if cnt == 0:
            break
        i += 1
        if i <= 50:
            candidate = f"{base}_{i}"
            continue
        # fallback: try timestamp+random a few times
        attempt = 0
        success = False
        while attempt < 10:
            candidate = f"{base}_{int(time.time())}_{random.randint(1,9999)}"
            if cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0] == 0:
                success = True
                break
            attempt += 1
        if success:
            break
        # final fallback: use short uuid, retry a few times
        for _ in range(10):
            candidate = f"{base}_{uuid.uuid4().hex[:8]}"
            if cur.execute('SELECT COUNT(*) FROM "音元拼音" WHERE 简拼=? OR 全拼=?', (candidate, vals.get("全拼"))).fetchone()[0] == 0:
                success = True
                break
        if success:
            break
        # extremely unlikely: sleep briefly and try again
        time.sleep(0.1)

    vals["简拼"] = candidate
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
            SAMPLE_ID,
        ),
    )
    conn.commit()
    print("inserted new row with 简拼:", vals["简拼"], "rowcount:", cur.rowcount)
