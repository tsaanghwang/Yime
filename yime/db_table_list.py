import sqlite3
from pathlib import Path

"""
# 连接不存在的文件时会自动创建
conn = sqlite3.connect('new_database.db')
conn.close()  # 这会创建一个空数据库文件
在这个项目中建有pinyin_db_manager.py模块，可以直接指定一个新文件名来创建空数据库：
from yime.pinyin_db_manager import PinyinDBManager
db = PinyinDBManager('new_database.db')  # 这会创建空数据库文件
"""
DB = Path(__file__).parent / "pinyin_hanzi.db"
with sqlite3.connect(DB) as conn:
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    print(cur.fetchall())

    cursor = conn.cursor()
    cursor.execute("""
        SELECT name, tbl_name, sql FROM sqlite_master
        WHERE type='index' AND tbl_name='音元拼音'
    """)
    print(cursor.fetchall())

import sqlite3
conn = sqlite3.connect("pinyin_hanzi.db")
cursor = conn.cursor()

# 检查表是否存在
cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='数字标调拼音'")
print("表存在:", cursor.fetchone() is not None)

# 获取表结构
cursor.execute("PRAGMA table_info('数字标调拼音')")
print("表结构:")
for col in cursor.fetchall():
    print(col)

conn.close()