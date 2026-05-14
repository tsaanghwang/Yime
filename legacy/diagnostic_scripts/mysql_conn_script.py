"""Legacy MySQL connectivity probe for a local root account."""

import os

import pymysql


def main() -> None:
    password = os.environ.get("MYSQL_ROOT_PASSWORD")
    print("repr(MYSQL_ROOT_PASSWORD) ->", repr(password))

    if password is None:
        print("未设置 MYSQL_ROOT_PASSWORD；该脚本仅保留作本地环境连通性诊断。")
        return

    try:
        conn = pymysql.connect(
            host="127.0.0.1",
            user="root",
            password=password,
            port=3306,
            charset="utf8mb4",
        )
        with conn.cursor() as cur:
            cur.execute("SELECT USER(), CURRENT_USER();")
            print("OK:", cur.fetchall())
        conn.close()
    except Exception as error:
        print("连接失败：", repr(error))


if __name__ == '__main__':
    main()
