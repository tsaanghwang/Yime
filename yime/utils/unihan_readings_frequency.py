from __future__ import annotations

import sqlite3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_UNIHAN_READINGS_DB = REPO_ROOT / "external_data" / "unihan_readings" / "unihan_readings.db"


def _view_exists(conn: sqlite3.Connection, view_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'view' AND name = ?",
        (view_name,),
    ).fetchone()
    return row is not None


def load_tghz2013_char_frequencies(db_path: Path = DEFAULT_UNIHAN_READINGS_DB) -> dict[str, int]:
    """Load 《通用规范汉字表》8105 字及其 BCC 单字频（来自 unihan_readings.db 视图）。"""
    if not db_path.exists():
        return {}

    conn = sqlite3.connect(db_path)
    try:
        if _view_exists(conn, "view_tghz2013_frequency"):
            query = """
                SELECT hanzi, frequency
                FROM view_tghz2013_frequency
            """
        else:
            query = """
                SELECT h.hanzi, hf.frequency
                FROM hanzi h
                INNER JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
                INNER JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
                WHERE u.kTGHZ2013 IS NOT NULL AND TRIM(u.kTGHZ2013) <> ''
            """
        frequency_by_char: dict[str, int] = {}
        for hanzi, frequency in conn.execute(query):
            key = str(hanzi or "").strip()
            if not key:
                continue
            try:
                freq = int(frequency or 0)
            except (TypeError, ValueError):
                freq = 0
            previous = frequency_by_char.get(key)
            if previous is None or freq > previous:
                frequency_by_char[key] = freq
        return frequency_by_char
    finally:
        conn.close()
