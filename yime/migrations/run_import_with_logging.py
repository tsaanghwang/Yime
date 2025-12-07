import sqlite3, sys
from pathlib import Path

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT))

from pinyin_importer import PinyinImporter

_orig_connect = sqlite3.connect

def _logged_connect(*a, **kw):
    conn = _orig_connect(*a, **kw)

    class CursorWrapper:
        def __init__(self, cur):
            self._cur = cur
        def executemany(self, sql, seq_of_params):
            try:
                return self._cur.executemany(sql, seq_of_params)
            except Exception:
                print("=== executemany SQL ===")
                print(sql)
                try:
                    sample = list(seq_of_params)[:10]
                    print("=== sample params (first 10) ===")
                    for p in sample:
                        print(p)
                except Exception:
                    print("Could not iterate params")
                raise
        def execute(self, *args, **kw):
            return self._cur.execute(*args, **kw)
        def fetchone(self):
            return self._cur.fetchone()
        def fetchall(self):
            return self._cur.fetchall()
        def __iter__(self):
            return iter(self._cur)
        def __getattr__(self, name):
            return getattr(self._cur, name)

    class ConnWrapper:
        def __init__(self, conn):
            self._conn = conn
        def cursor(self, *ca, **ck):
            cur = self._conn.cursor(*ca, **ck)
            return CursorWrapper(cur)
        def __getattr__(self, name):
            return getattr(self._conn, name)

    return ConnWrapper(conn)

sqlite3.connect = _logged_connect

SAMPLE = {
    999001: "abcd",
    999002: "abce",
    999003: "abcf",
    999004: "abbb",
    999005: "abbc",
    999006: "abcc",
}

if __name__ == "__main__":
    p = PinyinImporter()
    try:
        print("Running import (will attempt to write).")
        p.import_pinyin(SAMPLE)
        print("Import finished.")
    except Exception as e:
        print("Import raised:", type(e), e)
        sys.exit(1)
