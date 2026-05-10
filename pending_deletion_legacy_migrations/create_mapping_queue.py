from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"

DDL = """
CREATE TABLE IF NOT EXISTS mapping_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_table TEXT NOT NULL,
  target_pk INTEGER NOT NULL,
  hanzi TEXT,
  phoneme_key TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_queue_status ON mapping_queue(status);
"""

if __name__ == "__main__":
    DB.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(str(DB)) as conn:
        conn.executescript(DDL)
        conn.commit()
    print("mapping_queue created (if not existed) in:", DB)
