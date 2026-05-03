from pathlib import Path
import sqlite3
from typing import List

DB = Path(__file__).resolve().parent.parent / "pinyin_hanzi.db"

def codepoints(s: str) -> List[str]:
    if s is None:
        return []
    return [f"U+{ord(ch):06X}" for ch in s]

def fmt_row(row):
    d = dict(row)
    out = []
    out.append(f"编号: {d.get('编号')}")
    for col in ('全拼','简拼','干音','映射编号'):
        if col in d:
            out.append(f"{col}: {d[col]!r} -> {codepoints(d[col]) if isinstance(d[col], str) else d[col]}")
        else:
            # 若列名不同，列出可用列名以便排查
            out.append(f"{col}: <missing> (available cols: {list(d.keys())})")
    return "\n".join(out)

def main(limit=20):
    if not DB.exists():
        print("数据库不存在:", DB)
        return
    with sqlite3.connect(str(DB)) as conn:
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        print("DB:", DB.resolve())
        print("\n表结构 (PRAGMA table_info):")
        for r in cur.execute("PRAGMA table_info('音元拼音')"):
            print(dict(r))
        print("\n前几行（解析为 U+ 格式）:")
        for row in cur.execute('SELECT 编号, 全拼, 简拼, 干音, 映射编号 FROM "音元拼音" ORDER BY 编号 LIMIT ?', (limit,)):
            print(fmt_row(row))
            print("-" * 40)

if __name__ == "__main__":
    main()
