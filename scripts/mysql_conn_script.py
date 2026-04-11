import os
import pymysql

pw = os.environ.get("MYSQL_ROOT_PASSWORD")
print("repr(MYSQL_ROOT_PASSWORD) ->", repr(pw))
try:
    conn = pymysql.connect(host="127.0.0.1", user="root", password=pw, port=3306, charset="utf8mb4")
    with conn.cursor() as cur:
        cur.execute("SELECT USER(), CURRENT_USER();")
        print("OK:", cur.fetchall())
    conn.close()
except Exception as e:
    print("连接失败：", repr(e))
