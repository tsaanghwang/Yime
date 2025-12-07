import os, sys, pymysql
pw = os.environ.get("MYSQL_PASSWORD","YourPass")   # 不要把真实密码贴到聊天里
for h in ("127.0.0.1","localhost"):
    try:
        conn = pymysql.connect(host=h, port=3306, user="root", password=pw, connect_timeout=5)
        conn.close()
        print("OK connect via", h)
    except Exception as e:
        print("failed via", h, ":", e)
