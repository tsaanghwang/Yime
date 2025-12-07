# 不指定 filepath，按你自己决定放哪里（例如 temp.py）
from pathlib import Path
import sqlite3

DB = Path(r"C:\Users\Freeman Golden\OneDrive\Yime\yime\pinyin_hanzi.db")
SQL = """
SELECT COUNT(*) AS duplicate_groups
FROM (
  SELECT "简拼"
  FROM "音元拼音"
  WHERE "简拼" IS NOT NULL
  GROUP BY "简拼"
  HAVING COUNT(*) > 1
);
"""

def main():
    con = sqlite3.connect(str(DB))
    try:
        cur = con.cursor()
        cur.execute(SQL)
        row = cur.fetchone()
        print("duplicate_groups =", row[0] if row is not None else 0)
    finally:
        con.close()

if __name__ == "__main__":
    main()
