import os
import sys
import argparse
import pymysql

HOST = os.environ.get("MYSQL_HOST", "127.0.0.1")
USER = os.environ.get("MYSQL_USER", "root")
PORT = int(os.environ.get("MYSQL_PORT", 3306))
DATABASE = os.environ.get("MYSQL_DB", "ecommerce")  # 可选：指定要连接的数据库
PASSWORD = ""  # 临时明文密码，仅用于非交互调试，完成后请移除

def get_password(args):
    # 优先：命令行参数
    if args.password:
        return args.password
    # 次选：环境变量
    env_pw = os.environ.get("MYSQL_PASSWORD")
    if env_pw:
        return env_pw
    # 次选：密码文件路径（env 或参数）
    pw_file = args.password_file or os.environ.get("MYSQL_PASSWORD_FILE")
    if pw_file and os.path.isfile(pw_file):
        return open(pw_file, "r", encoding="utf-8").read().strip()
    # 回退：使用文件顶部硬编码密码（仅作临时测试）
    if 'PASSWORD' in globals() and PASSWORD:
        return PASSWORD
    # 非交互或无凭据时失败
    return None

def main():
    p = argparse.ArgumentParser(description="Check MySQL connection")
    p.add_argument("--host", default=os.environ.get("MYSQL_HOST","127.0.0.1"))
    p.add_argument("--port", type=int, default=int(os.environ.get("MYSQL_PORT",3306)))
    p.add_argument("--user", default=os.environ.get("MYSQL_USER","root"))
    p.add_argument("--password", help="Password (use only in secure contexts)")
    p.add_argument("--password-file", help="Path to file containing password")
    p.add_argument("--database", default=os.environ.get("MYSQL_DB",""))
    args = p.parse_args()

    pw = get_password(args)
    if not pw:
        print("未提供密码且当前终端不可交互。请通过 --password、环境变量 MYSQL_PASSWORD 或 MYSQL_PASSWORD_FILE 提供密码。", file=sys.stderr)
        sys.exit(2)

    try:
        conn = pymysql.connect(
            host=args.host,
            user=args.user,
            password=pw,
            port=args.port,
            charset='utf8mb4',
            use_unicode=True,
            connect_timeout=5,
            database=args.database or None
        )
        print("连接成功！")
        conn.close()
    except Exception as e:
        print("连接失败：", repr(e))
        sys.exit(1)

if __name__ == "__main__":
    main()
