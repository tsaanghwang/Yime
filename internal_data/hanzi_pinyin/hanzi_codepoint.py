# hanzi_codepoint.py
import sqlite3
from pathlib import Path

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")

BLOCKS = [
    (0x3007, 0x3007,       "小写零字"),
    (0x4E00, 0x9FFF,       "基本汉字"),
    (0x3400, 0x4DBF,       "扩展A"),
    (0x20000, 0x2A6DF,     "扩展B"),
    (0x2A700, 0x2B73F,     "扩展C"),
    (0x2B740, 0x2B81F,     "扩展D"),
    (0x2B820, 0x2CEAF,     "扩展E"),
    (0x2CEB0, 0x2EBEF,     "扩展F"),
    (0x30000, 0x3134F,     "扩展G"),
    (0x31350, 0x323AF,     "扩展H"),
    (0x2EBF0, 0x2EE5F,     "扩展I"),
    (0xF900, 0xFAFF,       "兼容汉字"),
    (0x2F800, 0x2FA1F,     "兼容补充"),
    (0x2F00, 0x2FDF,       "康熙部首"),
    (0x2FF0, 0x2FFF,       "表意文字描述符"),
    (0x31C0, 0x31EF,       "CJK笔画"),
]


def build_db():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS hanzi")

    cur.execute("""
        CREATE TABLE hanzi (
            codepoint   TEXT PRIMARY KEY,
            hanzi       TEXT NOT NULL,
            block       TEXT
        )
    """)

    cur.execute("CREATE INDEX idx_block ON hanzi(block)")

    conn.commit()

    batch = []
    total = 0

    for start, end, block_name in BLOCKS:
        count = 0
        for cp in range(start, end + 1):
            try:
                char = chr(cp)
                batch.append((
                    f"U+{cp:04X}",
                    char,
                    block_name
                ))
                count += 1
                total += 1

                if len(batch) >= 5000:
                    cur.executemany(
                        "INSERT OR IGNORE INTO hanzi VALUES (?,?,?)",
                        batch
                    )
                    batch = []
                    conn.commit()

            except Exception:
                continue

        if batch:
            cur.executemany(
                "INSERT OR IGNORE INTO hanzi VALUES (?,?,?)",
                batch
            )
            batch = []
            conn.commit()

        print(f"{block_name}: {count:,} 个")

    conn.close()
    print(f"\n合计: {total:,} 个汉字")
    print(f"数据库: {DB_FILE}")


def query_demo():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    print("\n── 查询示例 ──")

    cur.execute("SELECT * FROM hanzi WHERE hanzi = ?", ("龙",))
    print(f"查'龙': {cur.fetchone()}")

    cur.execute("SELECT hanzi, block FROM hanzi WHERE block = '基本汉字' LIMIT 5")
    print(f"基本汉字前5个: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    build_db()
    query_demo()
