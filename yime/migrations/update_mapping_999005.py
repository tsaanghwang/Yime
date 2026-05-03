from pathlib import Path
import sqlite3, sys
DB = Path(__file__).parents[1] / "pinyin_hanzi.db"


def main() -> int:
    with sqlite3.connect(str(DB)) as conn:
        cur = conn.cursor()
        cur.execute('UPDATE "音元拼音" SET 映射编号=? WHERE 编号=?', (999005, 1))
        conn.commit()
        print("updated rows:", cur.rowcount)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
