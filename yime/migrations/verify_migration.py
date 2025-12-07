import os, sqlite3, pymysql, random, sys, argparse, getpass

def _get_password():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--password")
    p.add_argument("--password-file")
    args, _ = p.parse_known_args()
    if args.password:
        return args.password
    env_pw = os.environ.get("MYSQL_PASSWORD")
    if env_pw:
        return env_pw
    pw_file = args.password_file or os.environ.get("MYSQL_PASSWORD_FILE")
    if pw_file and os.path.isfile(pw_file):
        with open(pw_file, "r", encoding="utf-8") as f:
            return f.read().strip()
    # interactive fallback only if tty
    if sys.stdin.isatty():
        return getpass.getpass("MySQL password: ")
    print("No MySQL password provided. Use MYSQL_PASSWORD / MYSQL_PASSWORD_FILE or --password.", file=sys.stderr)
    sys.exit(2)

SQLITE_DB = r"C:\Users\Freeman Golden\OneDrive\Yime\yime\pinyin_hanzi.db"
MYSQL_CFG = {
    "host": os.environ.get("MYSQL_HOST", "127.0.0.1"),
    "port": int(os.environ.get("MYSQL_PORT", 3306)),
    "user": os.environ.get("MYSQL_USER", "root"),
    "password": _get_password(),
    "db": os.environ.get("MYSQL_DB", "yime"),
    "charset": "utf8mb4",
}

def get_sqlite_tables(conn):
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    return [r[0] for r in cur.fetchall()]

def count_sqlite(conn, table):
    cur = conn.cursor()
    cur.execute(f"SELECT COUNT(1) FROM `{table}`")
    return cur.fetchone()[0]

def count_mysql(conn, table):
    cur = conn.cursor()
    cur.execute(f"SELECT COUNT(1) FROM `{table}`")
    return cur.fetchone()[0]

def sample_sqlite(conn, table, n=5):
    cur = conn.cursor()
    cur.execute(f"PRAGMA table_info('{table}')")
    cols = [r[1] for r in cur.fetchall()]
    cur.execute(f"SELECT * FROM `{table}` LIMIT 1000")
    rows = cur.fetchall()
    return cols, random.sample(rows, min(n, len(rows)))

def sample_mysql(conn, table, cols, n=5):
    cur = conn.cursor()
    qcols = ", ".join([f"`{c}`" for c in cols])
    cur.execute(f"SELECT {qcols} FROM `{table}` LIMIT 1000")
    rows = cur.fetchall()
    return random.sample(rows, min(n, len(rows)))

def main():
    s_conn = sqlite3.connect(SQLITE_DB)
    m_conn = pymysql.connect(**MYSQL_CFG)
    try:
        tables = get_sqlite_tables(s_conn)
        ok = True
        for t in tables:
            try:
                s_cnt = count_sqlite(s_conn, t)
                m_cnt = count_mysql(m_conn, t)
            except Exception as e:
                print(f"[ERROR] table {t}: {e}")
                ok = False
                continue
            print(f"{t}: sqlite={s_cnt} mysql={m_cnt} {'OK' if s_cnt==m_cnt else 'MISMATCH'}")
            if s_cnt and s_cnt==m_cnt:
                cols, s_sample = sample_sqlite(s_conn, t, n=3)
                m_sample = sample_mysql(m_conn, t, cols, n=3)
                print(" sample sqlite -> mysql")
                for a,b in zip(s_sample, m_sample):
                    print("  ", a, "->", b)
        return 0 if ok else 2
    finally:
        s_conn.close()
        m_conn.close()

if __name__ == "__main__":
    raise SystemExit(main())
