"""Materialize four-position yinjie decomposition rows from ``pinyin_yime_code``.

Replaces the legacy Chinese ``音元拼音`` overview table: one row per syllable with
full four-code string and per-position columns (首音 / 干音 / 呼音 / 主音 / 末音 / 韵音 / 间音).

Population uses ``syllable.codec.yinjie.Yinjie`` — the same structure model as the
encode/decode main chain. ``yime_code_jianpin_draft`` uses draft simplify rules only.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from syllable.codec.yinjie import Yinjie
from syllable.codec.variable_length_yinyuan import to_variable_length_yinyuan_code

CREATE_YINJIE_SLOT_DECOMPOSITION_SQL = """
CREATE TABLE IF NOT EXISTS yinjie_slot_decomposition (
    pinyin_tone TEXT PRIMARY KEY,
    yime_code TEXT NOT NULL,
    yime_code_jianpin_draft TEXT NOT NULL,
    slot_shouyin TEXT NOT NULL,
    slot_ganyin TEXT NOT NULL,
    slot_huyin TEXT NOT NULL,
    slot_zhuyin TEXT NOT NULL,
    slot_moyin TEXT NOT NULL,
    slot_yunyin TEXT NOT NULL,
    slot_jianyin TEXT NOT NULL,
    code_source TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
"""

CREATE_YINJIE_SLOT_DECOMPOSITION_INDEX_SQL = (
    "CREATE INDEX IF NOT EXISTS idx_yinjie_slot_decomposition_yime_code "
    "ON yinjie_slot_decomposition(yime_code)"
)


@dataclass(frozen=True)
class YinjieSlotDecompositionRow:
    pinyin_tone: str
    yime_code: str
    yime_code_jianpin_draft: str
    slot_shouyin: str
    slot_ganyin: str
    slot_huyin: str
    slot_zhuyin: str
    slot_moyin: str
    slot_yunyin: str
    slot_jianyin: str
    code_source: str

    def as_tuple(self) -> tuple[str, ...]:
        return (
            self.pinyin_tone,
            self.yime_code,
            self.yime_code_jianpin_draft,
            self.slot_shouyin,
            self.slot_ganyin,
            self.slot_huyin,
            self.slot_zhuyin,
            self.slot_moyin,
            self.slot_yunyin,
            self.slot_jianyin,
            self.code_source,
        )


def build_decomposition_row(
    pinyin_tone: str,
    yime_code: str,
    code_source: str,
) -> YinjieSlotDecompositionRow:
    """Derive position columns from a canonical four-character yime code."""
    normalized_code = str(yime_code or "").strip()
    if len(normalized_code) != 4:
        raise ValueError(f"yime_code 长度应为 4，实际为 {len(normalized_code)}: {normalized_code!r}")

    yinjie = Yinjie.from_code(normalized_code)
    variable_length_code = to_variable_length_yinyuan_code(normalized_code)
    return YinjieSlotDecompositionRow(
        pinyin_tone=str(pinyin_tone or "").strip(),
        yime_code=normalized_code,
        yime_code_jianpin_draft=variable_length_code,
        slot_shouyin=yinjie.initial or "",
        slot_ganyin=yinjie.ganyin_code,
        slot_huyin=yinjie.ascender or "",
        slot_zhuyin=yinjie.peak or "",
        slot_moyin=yinjie.descender or "",
        slot_yunyin=yinjie.get_yunyin_code(),
        slot_jianyin=yinjie.get_jianyin_code(),
        code_source=str(code_source or "").strip() or "unknown",
    )


def ensure_yinjie_slot_decomposition_schema(conn: sqlite3.Connection) -> None:
    conn.execute(CREATE_YINJIE_SLOT_DECOMPOSITION_SQL)
    conn.execute(CREATE_YINJIE_SLOT_DECOMPOSITION_INDEX_SQL)


def sync_yinjie_slot_decomposition(conn: sqlite3.Connection) -> int:
    """Rebuild decomposition rows from the current ``pinyin_yime_code`` table."""
    ensure_yinjie_slot_decomposition_schema(conn)
    source_rows = conn.execute(
        """
        SELECT pinyin_tone, yime_code, code_source
        FROM pinyin_yime_code
        ORDER BY pinyin_tone
        """
    ).fetchall()

    conn.execute("DELETE FROM yinjie_slot_decomposition")
    insert_rows: list[tuple[str, ...]] = []
    for pinyin_tone, yime_code, code_source in source_rows:
        row = build_decomposition_row(
            str(pinyin_tone or ""),
            str(yime_code or ""),
            str(code_source or ""),
        )
        insert_rows.append(row.as_tuple())

    if insert_rows:
        conn.executemany(
            """
            INSERT INTO yinjie_slot_decomposition (
                pinyin_tone,
                yime_code,
                yime_code_jianpin_draft,
                slot_shouyin,
                slot_ganyin,
                slot_huyin,
                slot_zhuyin,
                slot_moyin,
                slot_yunyin,
                slot_jianyin,
                code_source,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """,
            insert_rows,
        )
    return len(insert_rows)
