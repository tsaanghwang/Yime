from pathlib import Path
import sqlite3, sys, pathlib

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
PLACEHOLDERS = {
    999001: ("abcd", "bcd"),
    999002: ("abce", "bce"),
    999003: ("abcf", "bcf"),
    999004: ("abbb", "bbb"),
    999005: ("abbc", "bbc"),
    999006: ("abcc", "bcc"),
}

if not DB.exists():
    print("DB not found:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    cols = [r[1] for r in cur.execute("PRAGMA table_info('hanzi_phoneme_mapping')").fetchall()]
    print("hanzi_phoneme_mapping columns:", cols)

    # choose candidate id column names in priority order
    candidates = [c for c in ("id", "编号", "映射编号", "mapping_id") if c in cols]
    if not candidates:
        print("No known primary-like column found among", cols)
        sys.exit(2)
    target_col = candidates[0]
    print("Using target column for placeholder inserts:", target_col)

    # ensure hanzi and phoneme_code exist as columns, else use first available text columns
    def choose(col_names, fallback):
        return next((c for c in col_names if c in cols), fallback)

    hanzi_col = choose(["hanzi", "汉字", "character"], None)
    phon_col = choose(["phoneme_code", "phoneme", "code", "phon"], None)

    insert_cols = [target_col]
    if hanzi_col:
        insert_cols.append(hanzi_col)
    if phon_col:
        insert_cols.append(phon_col)

    placeholders_q = "(" + ",".join("?" for _ in insert_cols) + ")"
    insert_sql = f"INSERT OR IGNORE INTO hanzi_phoneme_mapping ({','.join(insert_cols)}) VALUES {placeholders_q}"
    print("Prepared SQL:", insert_sql)

    inserted = 0
    for mid, (hanzi, phon) in PLACEHOLDERS.items():
        vals = [mid]
        if hanzi_col:
            vals.append(hanzi)
        if phon_col:
            vals.append(phon)
        try:
            cur.execute(insert_sql, vals)
            if cur.rowcount:
                inserted += 1
        except Exception as e:
            print("failed to insert", mid, ":", e)
    conn.commit()
    print("Inserted/ignored placeholders:", inserted)

db = pathlib.Path("yime/pinyin_hanzi.db")
with sqlite3.connect(str(db)) as conn:
    for r in conn.execute("SELECT id, hanzi, phoneme_code, source FROM hanzi_phoneme_mapping WHERE id BETWEEN 999001 AND 999006 ORDER BY id"):
        print(r)
