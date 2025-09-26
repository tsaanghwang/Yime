import os
import sys
import argparse
import getpass

# existing imports kept
import sqlite3
import pymysql
from pymysql.constants import CLIENT

def get_password_from_sources(default_user):
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--password")
    p.add_argument("--password-file")
    args, _ = p.parse_known_args()

    # 1. CLI arg
    if args.password:
        return args.password
    # 2. ENV
    env_pw = os.environ.get("MYSQL_PASSWORD")
    if env_pw:
        return env_pw
    # 3. password file (path from arg or env)
    pw_file = args.password_file or os.environ.get("MYSQL_PASSWORD_FILE")
    if pw_file and os.path.isfile(pw_file):
        try:
            with open(pw_file, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception:
            pass
    # 4. system keyring (optional dependency)
    try:
        import keyring
        kr = keyring.get_password("yime-mysql", default_user)
        if kr:
            return kr
    except Exception:
        pass
    # 5. interactive prompt only if tty
    if sys.stdin.isatty():
        try:
            return getpass.getpass(prompt=f"Password for {default_user}: ")
        except Exception:
            pass
    # none found
    return None

SQLITE_DB = r"C:\Users\Freeman Golden\OneDrive\Yime\yime\pinyin_hanzi.db"  # adjust or pass as arg
BATCH = 1000

# MySQL connection from env
MYSQL = dict(
    host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
    port=int(os.environ.get("MYSQL_PORT", 3306)),
    user=os.environ.get("MYSQL_USER", "root"),
    password=os.environ.get("MYSQL_PASSWORD", ""),   # may be overwritten below
    db=os.environ.get("MYSQL_DB", "yime"),
    charset="utf8mb4",
    client_flag=CLIENT.MULTI_STATEMENTS
)

if not MYSQL.get("password"):
    pw = get_password_from_sources(MYSQL.get("user"))
    if not pw:
        print("未提供密码。请设置 MYSQL_PASSWORD 或 MYSQL_PASSWORD_FILE，或将密码存入系统 keyring（可选）。", file=sys.stderr)
        sys.exit(2)
    MYSQL["password"] = pw

def map_type(sqlite_type: str) -> str:
    t = (sqlite_type or "").upper()
    if "INT" in t: return "BIGINT"
    if "CHAR" in t or "CLOB" in t or "TEXT" in t: return "TEXT"
    if "BLOB" in t: return "LONGBLOB"
    if "REAL" in t or "FLOA" in t or "DOUB" in t: return "DOUBLE"
    if "NUM" in t or "DEC" in t: return "DECIMAL(38,10)"
    return "TEXT"

def get_tables(sqlite_conn):
    cur = sqlite_conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    return [r[0] for r in cur.fetchall()]

def migrate_table(sqlite_conn, mysql_conn, table):
    s_cur = sqlite_conn.cursor()
    s_cur.execute(f"PRAGMA table_info('{table}')")
    cols = s_cur.fetchall()  # cid,name,type,notnull,dflt_value,pk

    col_defs = []
    col_names = []
    pk_cols = []
    for cid, name, ctype, notnull, dflt, pk in cols:
        col_names.append(name)
        mapped = map_type(ctype)
        # 如果该列是主键且原来映射为 TEXT/LONGBLOB，改成可索引的 VARCHAR(191)
        if pk and mapped in ("TEXT", "LONGBLOB"):
            col_type = "VARCHAR(191)"
        else:
            col_type = mapped
        col_defs.append(f"`{name}` {col_type}")
        if pk:
            pk_cols.append(name)

    create_sql = f"CREATE TABLE IF NOT EXISTS `{table}` ({', '.join(col_defs)}"
    if pk_cols:
        create_sql += ", PRIMARY KEY(" + ",".join(f"`{c}`" for c in pk_cols) + ")"
    create_sql += ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"

    with mysql_conn.cursor() as mcur:
        mcur.execute(create_sql)
        mysql_conn.commit()

    # copy rows in batches
    s_cur.execute(f"SELECT COUNT(1) FROM `{table}`")
    total = s_cur.fetchone()[0]
    offset = 0
    placeholders = ",".join(["%s"] * len(col_names))
    # Use IGNORE to skip rows that would violate unique/PK constraints.
    # Alternatively use ON DUPLICATE KEY UPDATE ... to merge.
    insert_sql = f"INSERT IGNORE INTO `{table}` (`{ '`,`'.join(col_names) }`) VALUES ({placeholders})"

    while offset < total:
        s_cur.execute(f"SELECT {', '.join(col_names)} FROM `{table}` LIMIT {BATCH} OFFSET {offset}")
        rows = s_cur.fetchall()
        if not rows:
            break
        try:
            with mysql_conn.cursor() as mcur:
                mcur.executemany(insert_sql, rows)
            mysql_conn.commit()
        except pymysql.IntegrityError as e:
            # Fallback: try row-by-row to log problematic rows and continue
            print(f"Integrity error on batch at offset {offset}: {e}")
            for r in rows:
                try:
                    with mysql_conn.cursor() as mcur:
                        mcur.execute(insert_sql, r)
                    mysql_conn.commit()
                except pymysql.IntegrityError as e2:
                    print("Skipping row due to integrity error:", e2, "row:", r)
        offset += len(rows)
        print(f"{table}: migrated {offset}/{total}")

def ensure_database_exists(mysql_conf):
    dbname = mysql_conf.get("db")
    cfg = mysql_conf.copy()
    cfg.pop("db", None)
    conn = pymysql.connect(**cfg)
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{dbname}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
            conn.commit()
    finally:
        conn.close()

def main():
    sqlite_conn = sqlite3.connect(SQLITE_DB)
    # ensure target database exists before opening mysql_conn
    ensure_database_exists(MYSQL)
    mysql_conn = pymysql.connect(**MYSQL)
    try:
        tables = get_tables(sqlite_conn)
        for t in tables:
            print("Migrating", t)
            migrate_table(sqlite_conn, mysql_conn, t)
    finally:
        sqlite_conn.close()
        mysql_conn.close()

if __name__ == "__main__":
    main()
