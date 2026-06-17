from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.utils.char_frequency_policy import (  # noqa: E402
    DEFAULT_BCC_CHAR_FREQ_PATH,
    DEFAULT_UNIHAN_READINGS_DB,
    build_hanzi_frequency_table,
    import_hanzi_frequency_rows,
)

DB_FILE = SCRIPT_DIR / "hanzi_pinyin.db"
DEFAULT_FREQ_FILE = DEFAULT_BCC_CHAR_FREQ_PATH


def create_views(cur: sqlite3.Cursor) -> None:
    cur.execute("DROP VIEW IF EXISTS view_pinyin_by_frequency")
    cur.execute(
        """
        CREATE VIEW view_pinyin_by_frequency AS
        SELECT
            h.codepoint,
            h.hanzi,
            hr.common_reading AS pinyin,
            hr.readings AS pinyin_candidates,
            hf.frequency,
            hf.frequency_source,
            h.block,
            h.block_order
        FROM hanzi h
        LEFT JOIN hanzi_pinyin hr ON h.codepoint = hr.codepoint
        LEFT JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
        ORDER BY h.block_order ASC, h.codepoint ASC
        """
    )


def main() -> int:
    if not DEFAULT_FREQ_FILE.exists():
        raise FileNotFoundError(f"字频文件未找到: {DEFAULT_FREQ_FILE}")

    conn = sqlite3.connect(DB_FILE)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        cur = conn.cursor()
        build_hanzi_frequency_table(cur)
        conn.commit()

        bcc_applied, synthetic_applied, skipped_missing = import_hanzi_frequency_rows(
            cur,
            freq_path=DEFAULT_FREQ_FILE,
            unihan_db_path=DEFAULT_UNIHAN_READINGS_DB,
        )
        conn.commit()

        create_views(cur)
        conn.commit()

        print(
            "字频导入完成: "
            f"BCC {bcc_applied:,}，合成 {synthetic_applied:,}，"
            f"频文件无对应汉字 {skipped_missing:,}"
        )
        print(f"数据库: {DB_FILE}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
