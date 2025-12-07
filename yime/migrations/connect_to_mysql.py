import os
import sys
from mysql.connector import pooling, Error

HOST = os.environ.get("MYSQL_HOST", "127.0.0.1")  # 强制 TCP
PORT = int(os.environ.get("MYSQL_PORT", 3306))
USER = os.environ.get("MYSQL_USER", "root")
PASSWORD = os.environ.get("MYSQL_PASSWORD", "")    # 请通过环境变量提供密码
DATABASE = os.environ.get("MYSQL_DB", "ecommerce")

if not PASSWORD:
    print("未提供密码。请在运行前设置环境变量 MYSQL_PASSWORD。", file=sys.stderr)
    sys.exit(2)

try:
    db_pool = pooling.MySQLConnectionPool(
        pool_name="my_pool",
        pool_size=5,
        host=HOST,
        port=PORT,
        user=USER,
        password=PASSWORD,
        database=DATABASE,
        connection_timeout=5
    )
    print("连接池创建成功！")
except Error as e:
    code = getattr(e, "errno", None)
    msg = getattr(e, "msg", str(e))
    print(f"连接池初始化失败： {code} {msg} (host={HOST}, port={PORT}, user={USER})", file=sys.stderr)
    print("检查要点：1) MySQL 服务是否运行；2) my.ini 中 bind-address/skip-networking；3) 防火墙是否阻止 3306；4) 使用 127.0.0.1 强制 TCP。", file=sys.stderr)
    sys.exit(1)

# 2. 从连接池获取连接并执行操作
def query_users():
    conn = None
    cursor = None
    try:
        conn = db_pool.get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users LIMIT 5")
        for row in cursor.fetchall():
            print(row)
    except Error as e:
        print("查询失败：", e, file=sys.stderr)
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

if __name__ == "__main__":
    query_users()
