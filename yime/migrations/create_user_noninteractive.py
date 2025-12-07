import os
import sys
import pymysql

def _read_root_password():
    # 优先从文件读取，再回退到环境变量
    pw_file = os.environ.get("MYSQL_ROOT_PASSWORD_FILE")
    if pw_file and os.path.isfile(pw_file):
        try:
            with open(pw_file, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception as e:
            print(f"无法读取密码文件 {pw_file}: {e}", file=sys.stderr)
            return None
    return os.environ.get("MYSQL_ROOT_PASSWORD")

root_pw = _read_root_password()
if not root_pw:
    raise SystemExit("请先设置环境变量 MYSQL_ROOT_PASSWORD_FILE 或 MYSQL_ROOT_PASSWORD（文件优先）")

# 用于创建的新用户密码，优先从 MYSQL_USER_PASSWORD，否则使用 root 密码（仅便捷用）
user_pw = os.environ.get("MYSQL_USER_PASSWORD", root_pw)

try:
    conn = pymysql.connect(host="127.0.0.1", user="root", password=root_pw, port=3306, autocommit=True, charset="utf8mb4")
except pymysql.err.OperationalError as e:
    raise SystemExit(f"无法连接 MySQL（可能密码错误或权限不足）：{e}")

try:
    with conn.cursor() as cur:
        cur.execute("CREATE USER IF NOT EXISTS 'yime_root'@'127.0.0.1' IDENTIFIED BY %s;", (user_pw,))
        cur.execute("GRANT ALL PRIVILEGES ON `yime`.* TO 'yime_root'@'127.0.0.1';")
        cur.execute("FLUSH PRIVILEGES;")
        print("用户创建并授权完成。")
finally:
    conn.close()
# 临时（当前 shell 有效）
