import os
import sys
try:
    import pymysql
except Exception as e:
    print("pymysql not installed. Install with: pip install pymysql")
    sys.exit(2)

host = os.environ.get("MYSQL_HOST", "localhost")
port = int(os.environ.get("MYSQL_PORT", 3306))
user = os.environ.get("MYSQL_USER", "root")
password = os.environ.get("MYSQL_PASSWORD", "")
db = os.environ.get("MYSQL_DB", "")

try:
    conn = pymysql.connect(host=host, port=port, user=user, password=password, database=db, connect_timeout=5)
    with conn.cursor() as cur:
        cur.execute("SELECT VERSION()")
        ver = cur.fetchone()
        cur.execute("SELECT DATABASE()")
        curdb = cur.fetchone()
        cur.execute("SELECT User, Host, plugin FROM mysql.user WHERE User='root'")
        user_info = cur.fetchall()
        cur.execute("SHOW GRANTS FOR 'root'@'localhost'")
        grants = cur.fetchall()
    conn.close()
    print("OK: connected to", host, "port", port, "user", user)
    print("MySQL VERSION:", ver)
    print("DATABASE:", curdb)
    print("USER INFO:", user_info)
    print("GRANTS:", grants)
    sys.exit(0)
except Exception as e:
    msg = str(e)
    if 'cryptography' in msg or 'sha256_password' in msg or 'caching_sha2_password' in msg:
        print("Connection failed:", e)
        print("原因：需要安装 'cryptography' 库以支持 sha256/caching_sha2_password 认证。")
        print("请在虚拟环境中运行：")
        print("  .\\venv\\Scripts\\python.exe -m pip install cryptography")
        sys.exit(1)
    print("Connection failed:", e)
    sys.exit(1)
