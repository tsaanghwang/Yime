"""Read-only access to the unified source lexicon."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Iterator

from .types import SourceCandidate, SourceReading


REQUIRED_TABLES = {
    "accepted_readings",
    "bcc_frequency",
    "canonical_readings",
    "rejections",
}


def _csv_tuple(value: object) -> tuple[str, ...]:
    return tuple(item for item in str(value or "").split(",") if item)


class SourceLexicon:
    """A query-only facade over ``source_lexicon.sqlite3``."""

    def __init__(self, database: Path):
        self.database = database.resolve()
        if not self.database.is_file():
            raise FileNotFoundError(f"source lexicon does not exist: {self.database}")
        self.connection = sqlite3.connect(
            f"file:{self.database.as_posix()}?mode=ro",
            uri=True,
        )
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA query_only = ON")
        existing = {
            str(row[0])
            for row in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        missing = REQUIRED_TABLES - existing
        if missing:
            self.connection.close()
            raise ValueError(
                "source lexicon is missing required tables: " + ", ".join(sorted(missing))
            )

    def close(self) -> None:
        self.connection.close()

    def __enter__(self) -> "SourceLexicon":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def readings(self, text: str) -> tuple[SourceReading, ...]:
        rows = self.connection.execute(
            """
            SELECT *
            FROM canonical_readings
            WHERE text = ?
            ORDER BY reading_rank, id
            """,
            (text,),
        )
        def optional(row: sqlite3.Row, key: str, default: object) -> object:
            return row[key] if key in row.keys() else default

        return tuple(
            SourceReading(
                reading_id=int(row["id"]),
                text=str(row["text"]),
                marked=str(row["marked_pinyin"]),
                numeric=str(row["numeric_pinyin"]),
                is_primary=bool(row["is_primary"]),
                bcc_frequency=int(row["bcc_frequency"]),
                sources=_csv_tuple(row["pinyin_sources"]),
                source_categories=_csv_tuple(row["reading_source_categories"]),
                pronunciation_scope=str(
                    optional(row, "pronunciation_scope", "standalone")
                ),
                neutral_tone_positions=tuple(
                    int(item)
                    for item in str(
                        optional(row, "neutral_tone_positions", "")
                    ).split(",")
                    if item
                ),
                neutral_tone_status=str(
                    optional(row, "neutral_tone_status", "none")
                ),
            )
            for row in rows
        )

    def candidate(self, text: str) -> SourceCandidate:
        frequency_row = self.connection.execute(
            "SELECT frequency FROM bcc_frequency WHERE text = ?",
            (text,),
        ).fetchone()
        categories = tuple(
            f"{row['source']}:{row['source_category']}"
            for row in self.connection.execute(
                """
                SELECT DISTINCT source, source_category
                FROM accepted_readings
                WHERE text = ?
                ORDER BY source, source_category
                """,
                (text,),
            )
        )
        rejections = tuple(
            str(row[0])
            for row in self.connection.execute(
                "SELECT DISTINCT reason FROM rejections WHERE text = ? ORDER BY reason",
                (text,),
            )
        )
        return SourceCandidate(
            text=text,
            bcc_frequency=int(frequency_row[0]) if frequency_row else 0,
            readings=self.readings(text),
            source_categories=categories,
            rejection_reasons=rejections,
        )

    def iter_high_frequency_candidates(
        self,
        *,
        limit: int,
        minimum_frequency: int = 1,
        minimum_text_length: int = 2,
    ) -> Iterator[SourceCandidate]:
        if limit < 1:
            return
        rows = self.connection.execute(
            """
            SELECT text
            FROM bcc_frequency
            WHERE frequency >= ? AND LENGTH(text) >= ?
            ORDER BY frequency DESC, text
            LIMIT ?
            """,
            (minimum_frequency, minimum_text_length, limit),
        )
        for row in rows:
            yield self.candidate(str(row[0]))
