import os
import sys
import argparse
import getpass
import pymysql

# 开发便利：如果你真的要在文件里写密码，可在此处设置（仅开发用，切勿提交到公开仓库）
DEFAULT_ROOT_PASSWORD = ""  # e.g. "YourDevRootPassword"

def read_password(cli_val, env_name, file_arg):
    if cli_val:
        return cli_val
    env = os.environ.get(env_name)
    if env:
        return env
    # file arg
    if file_arg and os.path.isfile(file_arg):
        with open(file_arg, "r", encoding="utf-8") as f:
            return f.read().strip()
    # 使用文件内的默认密码（开发快捷方式）
    if DEFAULT_ROOT_PASSWORD:
        return DEFAULT_ROOT_PASSWORD
    if sys.stdin.isatty():
        return getpass.getpass("Root password: ")
    return None

parser = argparse.ArgumentParser(description="Create DB and user on local MySQL.")
parser.add_argument("--root-password", help="Root password")
parser.add_argument("--root-password-file", help="File containing root password")
parser.add_argument("--db", default="yime", help="Database name to create")
parser.add_argument("--user", default="yime_user", help="User to create/grant")
parser.add_argument("--user-password", help="Password for created user (if omitted use same as root)")
parser.add_argument("--set-root-password", help="If provided, set root password to this value after operations")
args = parser.parse_args()

root_pw = read_password(args.root_password, "MYSQL_ROOT_PASSWORD", args.root_password_file)
if not root_pw:
    print("Root password not provided (use --root-password or MYSQL_ROOT_PASSWORD).", file=sys.stderr)
    sys.exit(2)

user_pw = args.user_password or root_pw

conn = pymysql.connect(host="127.0.0.1", user="root", password=root_pw, port=3306, charset="utf8mb4", autocommit=True)
try:
    with conn.cursor() as cur:
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{args.db}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
        try:
            cur.execute(f"CREATE USER IF NOT EXISTS `{args.user}`@'127.0.0.1' IDENTIFIED BY %s;", (user_pw,))
            cur.execute(f"CREATE USER IF NOT EXISTS `{args.user}`@'localhost' IDENTIFIED BY %s;", (user_pw,))
            cur.execute(f"GRANT ALL PRIVILEGES ON `{args.db}`.* TO `{args.user}`@'127.0.0.1';")
            cur.execute(f"GRANT ALL PRIVILEGES ON `{args.db}`.* TO `{args.user}`@'localhost';")
            cur.execute("FLUSH PRIVILEGES;")
            print(f"Database `{args.db}` ensured and user `{args.user}` created/granted.")
        except pymysql.err.OperationalError as e:
            # 权限不足时跳过用户创建并提示下一步操作
            print(f"Warning: 无法创建/授权用户 ({e}). 数据库已创建，但需要有权限的 MySQL 帐号手动创建用户并授权。")
            print("手动命令示例（在有权限的 mysql 客户端中运行）：")
            print(f"  CREATE USER '{args.user}'@'127.0.0.1' IDENTIFIED BY '<password>';")
            print(f"  GRANT ALL PRIVILEGES ON `{args.db}`.* TO '{args.user}'@'127.0.0.1'; FLUSH PRIVILEGES;")
        if args.set_root_password:
            cur.execute("ALTER USER 'root'@'localhost' IDENTIFIED BY %s;", (args.set_root_password,))
            cur.execute("ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY %s;", (args.set_root_password,))
            cur.execute("FLUSH PRIVILEGES;")
            print("Root password updated.")
finally:
    conn.close()
