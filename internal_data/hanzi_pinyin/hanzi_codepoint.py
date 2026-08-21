# hanzi_codepoint.py
import sqlite3
from pathlib import Path

from hanzi_catalog import create_hanzi_table, populate_hanzi

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")


def build_db():
    conn = sqlite3.connect(DB_FILE)

    def on_block(block_name: str, count: int) -> None:
        print(f"{block_name}: {count:,} 个")

    create_hanzi_table(conn, drop_existing=True)
    total = populate_hanzi(conn, on_block=on_block)
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
