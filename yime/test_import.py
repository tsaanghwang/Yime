import sqlite3
conn = sqlite3.connect("C:/Users/Freeman Golden/OneDrive/Yime/pinyin_hanzi.db")
print(conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall())
