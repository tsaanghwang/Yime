from __future__ import annotations

from dataclasses import dataclass
import sqlite3
from pathlib import Path

from .user_lexicon import UserLexiconStore


@dataclass(frozen=True)
class RuntimeReverseLookupRecord:
    text: str
    marked_pinyin: str
    numeric_pinyin: str
    yime_code: str
    entry_type: str

    def to_display_text(self) -> str:
        parts = [part for part in (self.marked_pinyin, self.numeric_pinyin) if part]
        pinyin_display = " / ".join(parts)
        if pinyin_display and self.yime_code:
            return f"{pinyin_display} | {self.yime_code}"
        return pinyin_display or self.yime_code


def looks_like_hanzi_text(text: str) -> bool:
    stripped = "".join(char for char in text.strip() if not char.isspace())
    if not stripped:
        return False
    return all(_is_cjk_unified_ideograph(char) for char in stripped)


def _is_cjk_unified_ideograph(char: str) -> bool:
    codepoint = ord(char)
    return (
        0x3400 <= codepoint <= 0x4DBF
        or 0x4E00 <= codepoint <= 0x9FFF
        or 0xF900 <= codepoint <= 0xFAFF
        or 0x20000 <= codepoint <= 0x2EBEF
    )


class RuntimeReverseLookup:
    def __init__(self, db_path: Path, user_db_path: Path | None = None) -> None:
        self.db_path = db_path
        self.user_lexicon = UserLexiconStore(user_db_path or db_path.with_name("user_lexicon.db"))

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(f"file:{self.db_path}?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        return connection

    def lookup_first(self, text: str) -> RuntimeReverseLookupRecord | None:
        stripped = text.strip()
        if not looks_like_hanzi_text(stripped):
            return None

        if len(stripped) > 1:
            user_entry = self.user_lexicon.lookup_first_phrase(stripped)
            if user_entry is not None:
                return RuntimeReverseLookupRecord(
                    text=user_entry.phrase,
                    marked_pinyin=user_entry.marked_pinyin,
                    numeric_pinyin=user_entry.numeric_pinyin,
                    yime_code=user_entry.yime_code,
                    entry_type="phrase",
                )

        with self._connect() as connection:
            if len(stripped) == 1:
                row = connection.execute(
                    """
                    SELECT hanzi AS text, marked_pinyin, pinyin_tone AS numeric_pinyin, yime_code
                    FROM char_lexicon
                    WHERE hanzi = ?
                    ORDER BY reading_rank, reading_weight DESC
                    LIMIT 1
                    """,
                    (stripped,),
                ).fetchone()
                if row is None:
                    return None
                return RuntimeReverseLookupRecord(
                    text=str(row["text"] or ""),
                    marked_pinyin=str(row["marked_pinyin"] or ""),
                    numeric_pinyin=str(row["numeric_pinyin"] or ""),
                    yime_code=str(row["yime_code"] or ""),
                    entry_type="char",
                )

            row = connection.execute(
                """
                SELECT
                    pv.phrase AS text,
                    COALESCE(pr.marked_pinyin, '') AS marked_pinyin,
                    pv.pinyin_tone AS numeric_pinyin,
                    pv.yime_code AS yime_code
                FROM phrase_lexicon_view pv
                LEFT JOIN phrase_readings pr
                    ON pr.phrase = pv.phrase
                   AND pr.numeric_pinyin = pv.pinyin_tone
                WHERE pv.phrase = ?
                ORDER BY pv.reading_rank, pv.phrase_frequency DESC, pr.reading_rank
                LIMIT 1
                """,
                (stripped,),
            ).fetchone()
            if row is None:
                return None
            return RuntimeReverseLookupRecord(
                text=str(row["text"] or ""),
                marked_pinyin=str(row["marked_pinyin"] or ""),
                numeric_pinyin=str(row["numeric_pinyin"] or ""),
                yime_code=str(row["yime_code"] or ""),
                entry_type="phrase",
            )
