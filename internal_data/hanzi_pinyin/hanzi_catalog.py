"""Shared Unicode CJK hanzi catalog: schema, blocks, and population."""

from __future__ import annotations

import sqlite3
from collections.abc import Callable
from typing import Optional

BLOCKS = [
    (0x3007, 0x3007, "小写零字"),
    (0x4E00, 0x9FFF, "基本汉字"),
    (0x3400, 0x4DBF, "扩展A"),
    (0x20000, 0x2A6DF, "扩展B"),
    (0x2A700, 0x2B73F, "扩展C"),
    (0x2B740, 0x2B81F, "扩展D"),
    (0x2B820, 0x2CEAF, "扩展E"),
    (0x2CEB0, 0x2EBEF, "扩展F"),
    (0x30000, 0x3134F, "扩展G"),
    (0x31350, 0x323AF, "扩展H"),
    (0x2EBF0, 0x2EE5F, "扩展I"),
    (0xF900, 0xFAFF, "兼容汉字"),
    (0x2F800, 0x2FA1F, "兼容补充"),
    (0x2F00, 0x2FDF, "康熙部首"),
    (0x2FF0, 0x2FFF, "表意文字描述符"),
    (0x31C0, 0x31EF, "CJK笔画"),
]

HANZI_DDL = """
    CREATE TABLE hanzi (
        codepoint   TEXT PRIMARY KEY,
        hanzi       TEXT NOT NULL,
        block       TEXT,
        block_order INTEGER NOT NULL DEFAULT 0
    )
"""


def format_codepoint(cp: int) -> str:
    return f"U+{cp:04X}"


def hanzi_table_exists(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'hanzi'"
    ).fetchone()
    return row is not None


def hanzi_count(conn: sqlite3.Connection) -> int:
    if not hanzi_table_exists(conn):
        return 0
    return conn.execute("SELECT COUNT(*) FROM hanzi").fetchone()[0]


def create_hanzi_table(conn: sqlite3.Connection, *, drop_existing: bool = False) -> None:
    cur = conn.cursor()
    if drop_existing:
        cur.execute("DROP TABLE IF EXISTS hanzi")
    cur.execute(HANZI_DDL)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_block ON hanzi(block)")
    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_block_order ON hanzi(block_order, codepoint)"
    )
    conn.commit()


def populate_hanzi(
    conn: sqlite3.Connection,
    *,
    on_block: Optional[Callable[[str, int], None]] = None,
) -> int:
    cur = conn.cursor()
    batch: list[tuple[str, str, str, int]] = []
    total = 0

    for block_idx, (start, end, block_name) in enumerate(BLOCKS):
        count = 0
        for cp in range(start, end + 1):
            try:
                char = chr(cp)
            except ValueError:
                continue
            batch.append((format_codepoint(cp), char, block_name, block_idx))
            count += 1
            total += 1
            if len(batch) >= 5000:
                cur.executemany(
                    "INSERT OR IGNORE INTO hanzi VALUES (?,?,?,?)",
                    batch,
                )
                batch = []
                conn.commit()

        if batch:
            cur.executemany(
                "INSERT OR IGNORE INTO hanzi VALUES (?,?,?,?)",
                batch,
            )
            batch = []
            conn.commit()

        if on_block is not None:
            on_block(block_name, count)

    return total


def rebuild_hanzi_catalog(conn: sqlite3.Connection) -> int:
    create_hanzi_table(conn, drop_existing=True)
    return populate_hanzi(conn)


def ensure_hanzi_catalog(conn: sqlite3.Connection) -> int:
    if hanzi_count(conn) > 0:
        return hanzi_count(conn)
    if not hanzi_table_exists(conn):
        create_hanzi_table(conn, drop_existing=False)
    count = populate_hanzi(conn)
    if count == 0:
        return hanzi_count(conn)
    return count
