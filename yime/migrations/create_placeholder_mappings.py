from pathlib import Path
import sqlite3
import sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"

# 根据你 run_sample_import.py 的 SAMPLE，填入占位映射
PLACEHOLDERS = {
    999001: ("abcd", "bcd"),
    999002: ("abce", "bce"),
    999003: ("abcf", "bcf"),
    999004: ("abbb", "bbb"),
    999005: ("abbc", "bbc"),
    999006: ("abcc", "bcc"),
}

if not DB.exists():
    print("数据库不存在:", DB); sys.exit(1)

with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    # 确保表存在（若你已创建过该表，这段只做保险检查）
    cur.execute("""
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
    """)
    inserted = 0
    for mid, (hanzi, phon) in PLACEHOLDERS.items():
        try:
            cur.execute(
                "INSERT OR IGNORE INTO hanzi_phoneme_mapping(id, hanzi, phoneme_code, codepoint_sequence, source) VALUES (?,?,?,?,?)",
                (mid, hanzi, phon, "", "placeholder"),
            )
            if cur.rowcount:
                inserted += 1
        except Exception as e:
            print("插入占位映射失败:", mid, e)
    conn.commit()
    print(f"占位映射处理完成，新增/忽略: {inserted}")
