from pathlib import Path
import sqlite3, json, csv, sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
if not DB.exists():
    print("数据库不存在:", DB); sys.exit(1)

def ensure_table(conn):
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS hanzi_phoneme_mapping (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hanzi TEXT NOT NULL,
      phoneme_code TEXT NOT NULL,
      codepoint_sequence TEXT,
      source TEXT,
      version INTEGER DEFAULT 1,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(hanzi, phoneme_code)
    );
    CREATE INDEX IF NOT EXISTS idx_hanzi_phoneme ON hanzi_phoneme_mapping(hanzi);
    """)

def insert_rows(conn, rows):
    cur = conn.cursor()
    for r in rows:
        hanzi = r.get("hanzi") or r.get("character") or r.get("char")
        phon = r.get("phoneme_code") or r.get("phoneme") or r.get("干音")
        cps = r.get("codepoint_sequence") or r.get("codepoints") or r.get("codepoint")
        src = r.get("source") or "import"
        if not hanzi or not phon:
            print("跳过不完整行:", r)
            continue
        try:
            cur.execute(
                "INSERT OR IGNORE INTO hanzi_phoneme_mapping(hanzi, phoneme_code, codepoint_sequence, source) VALUES(?,?,?,?)",
                (hanzi, phon, cps, src)
            )
        except Exception as e:
            print("插入失败:", e, r)
    conn.commit()
    print("导入完成，已写入 (忽略已存在)")

def load_input(path: Path):
    s = path.suffix.lower()
    if s == ".json":
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                # 支持 { "汉字": {"phoneme_code":..., "codepoint_sequence":...}, ... }
                out = []
                for k,v in data.items():
                    if isinstance(v, dict):
                        out.append({"hanzi": k, **v})
                    else:
                        # value might be direct codepoint sequence: treat as phoneme_key->codepoints? skip
                        pass
                return out
            elif isinstance(data, list):
                return data
    elif s in (".csv",):
        out=[]
        with path.open("r",encoding="utf-8") as f:
            rdr = csv.DictReader(f)
            for r in rdr:
                out.append(r)
        return out
    else:
        raise SystemExit("不支持的文件类型: " + s)

def main(argv=None):
    if not argv:
        argv = sys.argv[1:]
    if not argv:
        print("Usage: import_hanzi_phoneme_mapping.py <file.json|file.csv>"); return 2
    src = Path(argv[0])
    if not src.exists():
        print("文件不存在:", src); return 3
    rows = load_input(src)
    with sqlite3.connect(str(DB)) as conn:
        ensure_table(conn)
        insert_rows(conn, rows)

if __name__ == "__main__":
    sys.exit(main())
