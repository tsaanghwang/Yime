from pathlib import Path
import sqlite3
import csv
from utils_charfilter import is_allowed_code_char

DB = Path(__file__).parent / "pinyin_hanzi.db"
OUT = Path(__file__).parent / "mappings_export.csv"

def to_hex_list(s):
    if s is None:
        return ""
    return " ".join(f"U+{ord(ch):06X}" for ch in s)

# 替换掉直接使用 ord(...) 的拒绝逻辑，改为更宽松的判定
def accept_mapping_key(k: str) -> bool:
    # 旧：基于 ord(...) 的严格范围判断
    return bool(k) and all(is_allowed_code_char(ch) for ch in k)

with sqlite3.connect(str(DB)) as conn, open(OUT, "w", newline="", encoding="utf-8") as f:
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    writer = csv.writer(f)
    writer.writerow(["编号","全拼_raw","全拼_hex","简拼_raw","简拼_hex","干音_raw","干音_hex","映射编号"])
    for row in cur.execute('SELECT 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" ORDER BY 编号'):
        writer.writerow([
            row["编号"],
            row["全拼"],
            to_hex_list(row["全拼"]),
            row["简拼"],
            to_hex_list(row["简拼"]),
            row["干音"],
            to_hex_list(row["干音"]),
            row["映射编号"],
        ])
print("已导出:", OUT.resolve())
