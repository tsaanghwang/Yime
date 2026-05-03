import sqlite3
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "pinyin_hanzi.db"

def check_index_exists(conn: sqlite3.Connection, index_name: str) -> bool:
    """检查索引是否存在（在 sqlite_master 中）"""
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name = ?", (index_name,))
    return cur.fetchone() is not None

def list_table_and_indexes(db_path: Path):
    with sqlite3.connect(str(db_path)) as conn:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        print("tables:", cur.fetchall())

        cur.execute("""
            SELECT name, tbl_name, sql FROM sqlite_master
            WHERE type='index' AND tbl_name='音元拼音'
        """)
        print("音元拼音 indexes:", cur.fetchall())

        # 检查表是否存在
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='数字标调拼音'")
        print("表 '数字标调拼音' 存在:", cur.fetchone() is not None)

        # 获取表结构
        cur.execute("PRAGMA table_info('数字标调拼音')")
        print("数字标调拼音 表结构:")
        for col in cur.fetchall():
            print(col)

        # 验证索引存在（可在此处列出要验证的索引名）
        indexes_to_check = [
            "ux_音元拼音_简拼_nonnull",
            "ux_音元拼音_全拼",
            "sqlite_autoindex_音元拼音_1"  # 可能存在的自动索引名
        ]
        for idx in indexes_to_check:
            exists = check_index_exists(conn, idx)
            print(f"索引 '{idx}' 存在: {exists}")

if __name__ == "__main__":
    list_table_and_indexes(DB)
