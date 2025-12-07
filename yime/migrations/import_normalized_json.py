from pathlib import Path
import json, sqlite3, sys

ROOT = Path(__file__).parents[1]
JSON_PATH = ROOT / "pinyin_normalized.json"
DB = ROOT / "pinyin_hanzi.db"

if len(sys.argv) > 1:
    JSON_PATH = Path(sys.argv[1])
if len(sys.argv) > 2:
    DB = Path(sys.argv[2])
# 新增：可选第三个参数，逗号分隔的原拼音键，只处理这些键
include_keys = None
if len(sys.argv) > 3 and sys.argv[3].strip():
    include_keys = {s.strip() for s in sys.argv[3].split(",") if s.strip()}

if not JSON_PATH.exists():
    print("JSON not found:", JSON_PATH); sys.exit(1)
if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with open(JSON_PATH, "r", encoding="utf-8-sig") as f:
    data = json.load(f)

if not isinstance(data, dict):
    print("JSON must be an object mapping numbered-tone -> standard pinyin"); sys.exit(2)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    # ensure table exists (safe)
    cur.execute('''
    CREATE TABLE IF NOT EXISTS "拼音映射关系" (
        "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
        "原拼音类型" TEXT NOT NULL,
        "原拼音" TEXT NOT NULL,
        "目标拼音类型" TEXT NOT NULL,
        "目标拼音" TEXT NOT NULL,
        "数据来源" TEXT,
        "版本号" TEXT,
        "备注" TEXT,
        "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源")
    )
    ''')
    conn.commit()

    # insert base mappings: 数字标调 -> 标准拼音
    inserted = 0
    for key, val in data.items():
        if include_keys and key not in include_keys:
            continue
        try:
            num = str(key).strip()
            std = str(val).strip()
            cur.execute('''
            INSERT OR IGNORE INTO "拼音映射关系"
            ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
            VALUES (?,?,?,?,?,?,?)
            ''', ("数字标调", num, "标准拼音", std, "pinyin_normalized", "", "from pinyin_normalized.json"))
            if cur.rowcount:
                inserted += cur.rowcount

            # 同步插入反向：标准拼音 -> 数字标调，便于后续连表组合
            cur.execute('''
            INSERT OR IGNORE INTO "拼音映射关系"
            ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
            VALUES (?,?,?,?,?,?,?)
            ''', ("标准拼音", std, "数字标调", num, "pinyin_normalized_reverse", "", "reverse from pinyin_normalized.json"))
            if cur.rowcount:
                inserted += cur.rowcount
        except Exception as e:
            print("insert error for", key, val, e)
    conn.commit()

    # try to compose: if there is a mapping 标准拼音 -> 音元拼音, create 数字标调 -> 音元拼音
    composed = 0
    for key, val in data.items():
        if include_keys and key not in include_keys:
            continue
        std = str(val).strip()
        # find all 音元 targets for this standard pinyin
        rows = cur.execute('''
            SELECT 目标拼音 FROM "拼音映射关系"
            WHERE 原拼音类型 = ? AND 原拼音 = ? AND 目标拼音类型 = ?
        ''', ("标准拼音", std, "音元拼音")).fetchall()
        for r in rows:
            target_audio = r[0]
            cur.execute('''
            INSERT OR IGNORE INTO "拼音映射关系"
            ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
            VALUES (?,?,?,?,?,?,?)
            ''', ("数字标调", str(key).strip(), "音元拼音", target_audio, "pinyin_normalized_composed", "", f"composed via standard:{std}"))
            if cur.rowcount:
                composed += cur.rowcount
    conn.commit()

    # 额外合成：通过 标准拼音 -> 数字标调 和 数字标调 -> 音元拼音 的链路，生成 标准拼音 -> 音元拼音
    # 这样可以利用重复/多对多关系把标准拼音直接映射到音元拼音
    composed_std_to_audio = 0
    rows = cur.execute('''
        SELECT m1.原拼音 AS standard, m2.目标拼音 AS audio
        FROM "拼音映射关系" m1
        JOIN "拼音映射关系" m2
          ON m1.目标拼音 = m2.原拼音
        WHERE m1.原拼音类型 = '标准拼音'
          AND m1.目标拼音类型 = '数字标调'
          AND m2.原拼音类型 = '数字标调'
          AND m2.目标拼音类型 = '音元拼音'
    ''').fetchall()
    for standard, audio in rows:
        try:
            cur.execute('''
            INSERT OR IGNORE INTO "拼音映射关系"
            ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
            VALUES (?,?,?,?,?,?,?)
            ''', ("标准拼音", standard, "音元拼音", audio, "pinyin_normalized_composed_std_audio", "", f"composed via numeric"))
            if cur.rowcount:
                composed_std_to_audio += cur.rowcount
        except Exception as e:
            print("compose std->audio insert error:", standard, audio, e)
    conn.commit()

    # summary + preview
    total = cur.execute('SELECT COUNT(*) FROM "拼音映射关系" WHERE 数据来源 LIKE ?', ("pinyin_normalized%",)).fetchone()[0]
    print("inserted base mappings (数字标调->标准拼音) approx:", inserted)
    print("inserted composed mappings (数字标调->音元拼音):", composed)
    print("inserted composed mappings (标准拼音->音元拼音):", composed_std_to_audio)
    print("total rows from this import source in DB:", total)
    print("\nsample (最多20) 数字标调 -> 标准拼音:")
    for r in cur.execute('SELECT ROWID, 原拼音, 目标拼音 FROM "拼音映射关系" WHERE 原拼音类型=? AND 目标拼音类型=? LIMIT 20', ("数字标调","标准拼音")):
        print(r)
    print("\nsample composed 数字标调 -> 音元拼音 (若有):")
    for r in cur.execute('SELECT ROWID, 原拼音, 目标拼音 FROM "拼音映射关系" WHERE 原拼音类型=? AND 目标拼音类型=? LIMIT 20', ("数字标调","音元拼音")):
        print(r)

# Run:
# ./venv/Scripts/python.exe ./yime/migrations/import_normalized_json.py
# or: ./venv/Scripts/python.exe ./yime/migrations/import_normalized_json.py ./yime/pinyin_normalized.json ./yime/pinyin_hanzi.db
