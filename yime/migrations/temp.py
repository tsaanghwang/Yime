import os
import sys
import pymysql
from pymysql import OperationalError

HOST = os.environ.get("MYSQL_HOST", "127.0.0.1")
PORT = int(os.environ.get("MYSQL_PORT", 3306))
USER = os.environ.get("MYSQL_USER", "root")
PASSWORD = os.environ.get("MYSQL_PASSWORD", "")  # 从环境获取，别在代码里写明文
DBNAME = os.environ.get("MYSQL_DB", "your_db")

def main():
    try:
        conn = pymysql.connect(host=HOST, port=PORT, user=USER, password=PASSWORD, autocommit=True)
        cur = conn.cursor()
        # 如果目标数据库不存在，这里会抛 1049；使用 root 创建数据库需要有权限
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{DBNAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
        cur.execute(f"GRANT ALL PRIVILEGES ON `{DBNAME}`.* TO 'appuser'@'127.0.0.1';")
        cur.execute(f"GRANT ALL PRIVILEGES ON `{DBNAME}`.* TO 'appuser'@'localhost';")
        cur.execute("FLUSH PRIVILEGES;")
        conn.close()
        print("done")
    except OperationalError as e:
        errno = e.args[0] if e.args else None
        if errno == 1045:
            print("Connection failed: Access denied (1045).")
            print("  - 检查 MYSQL_USER / MYSQL_PASSWORD 是否正确；")
            print("  - 尽量不要用 root 给脚本运行，建议创建 appuser 并授权；")
            print("  - 若需以 root 创建数据库，请在交互式 mysql 中用正确密码执行 CREATE DATABASE ...")
        elif errno == 1049:
            print("Connection succeeded but database unknown (1049).")
            print("  - 若你已用非 root 用户连接，请用 root 创建数据库或给该用户创建权限；")
        else:
            print("Connection failed:", e)
        sys.exit(1)
    except Exception as e:
        print("Unexpected error:", e)
        sys.exit(1)

if __name__ == "__main__":
    main()
