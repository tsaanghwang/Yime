#!/usr/bin/env python3
"""Import merged BCC char frequency + Unihan synthetic ladder into unihan_readings.db."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.utils.char_frequency_policy import (  # noqa: E402
    DEFAULT_BCC_CHAR_FREQ_PATH,
    build_hanzi_frequency_table,
    import_hanzi_frequency_rows,
)

DB_PATH = SCRIPT_DIR / "unihan_readings.db"
DEFAULT_FREQ_FILE = DEFAULT_BCC_CHAR_FREQ_PATH


def main() -> int:
    if not DEFAULT_FREQ_FILE.exists():
        raise FileNotFoundError(f"字频文件未找到: {DEFAULT_FREQ_FILE}")

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        cur = conn.cursor()
        if cur.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='hanzi'"
        ).fetchone() is None:
            raise RuntimeError("hanzi 主表不存在，请先运行 build_hanzi.py")

        build_hanzi_frequency_table(cur)
        conn.commit()

        bcc_applied, synthetic_applied, skipped_missing = import_hanzi_frequency_rows(
            cur,
            freq_path=DEFAULT_FREQ_FILE,
            unihan_db_path=DB_PATH,
        )
        conn.commit()

        print(
            "字频导入完成: "
            f"BCC {bcc_applied:,}，合成 {synthetic_applied:,}，"
            f"频文件无对应汉字 {skipped_missing:,}"
        )
        print(f"数据库: {DB_PATH}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
