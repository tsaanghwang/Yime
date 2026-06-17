"""Shared character and phrase frequency import policy for Yime.

Single-character (BCC merged char frequency is primary; integer counts, min observed 6).
When BCC has no hit, apply a fixed Unihan-column synthetic ladder strictly below 6:

  kTGHZ2013 -> 5, kHanyuPinlu -> 4, kXHC1983 -> 3, kHanyuPinyin -> 2, kMandarin -> 1, else 0

Multiple Unihan columns take the maximum synthetic tier. kHanyuPinlu uses a flat 4;
embedded Pinlu relative counts are intentionally ignored.

Multi-character phrases in the lexicon default to frequency 1 when BCC has no hit,
reflecting minimum attestation in the curated phrase inventory.
"""

from __future__ import annotations

import csv
import sqlite3
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BCC_CHAR_FREQ_PATH = (
    REPO_ROOT / "external_data" / "char_freq" / "merged_char_freq.txt"
)
DEFAULT_BCC_PHRASE_FREQ_PATH = (
    REPO_ROOT / "external_data" / "word_freq" / "merged_word_freq.txt"
)
DEFAULT_UNIHAN_READINGS_DB = (
    REPO_ROOT / "external_data" / "unihan_readings" / "unihan_readings.db"
)

BCC_SOURCE = "external_data/BCC-word-freq"
SYNTHETIC_NONE_SOURCE = "synthetic/none"
PHRASE_LEXICON_DEFAULT_FREQUENCY = 1

# Removed import chains / misleading snapshot keys purged on BCC import and runtime refresh.
LEGACY_FREQUENCY_METADATA_KEYS = (
    "prototype_xiandaihaiyu_phrase_freq_source",
    "prototype_xiandaihaiyu_phrase_freq_updated",
    "prototype_xiandaihaiyu_phrase_freq_skipped",
    "prototype_8105_frequency_source",
    "prototype_8105_frequency_imported_rows",
    "prototype_8105_frequency_skipped_rows",
    "prototype_8105_frequency_max_abs",
    "prototype_char_frequency_bridge_total_chars",
    "prototype_char_frequency_bridge_populated_before",
    "prototype_char_frequency_bridge_populated_after",
    "prototype_char_frequency_bridge_dominant_source",
)
LING_HANZI = "〇"
DIGIT_HANZI = "一二三四五六七八九十"

UNIHAN_COLUMN_NAMES = (
    "kTGHZ2013",
    "kHanyuPinlu",
    "kXHC1983",
    "kHanyuPinyin",
    "kMandarin",
)

UNIHAN_SYNTHETIC_TIERS: tuple[tuple[str, int, str], ...] = (
    ("kTGHZ2013", 5, "synthetic/kTGHZ2013"),
    ("kHanyuPinlu", 4, "synthetic/kHanyuPinlu"),
    ("kXHC1983", 3, "synthetic/kXHC1983"),
    ("kHanyuPinyin", 2, "synthetic/kHanyuPinyin"),
    ("kMandarin", 1, "synthetic/kMandarin"),
)


@dataclass(frozen=True)
class ResolvedCharFrequency:
    frequency: int
    source: str


def _column_present(value: object) -> bool:
    return bool(str(value or "").strip())


def synthetic_frequency_from_unihan_columns(
    columns: dict[str, object] | None,
) -> ResolvedCharFrequency:
    best_freq = 0
    best_source = SYNTHETIC_NONE_SOURCE
    for column, freq, source in UNIHAN_SYNTHETIC_TIERS:
        if _column_present((columns or {}).get(column)):
            if freq > best_freq:
                best_freq = freq
                best_source = source
    return ResolvedCharFrequency(best_freq, best_source)


def resolve_char_frequency(
    *,
    bcc_frequency: int | None,
    unihan_columns: dict[str, object] | None = None,
    bcc_source: str = BCC_SOURCE,
) -> ResolvedCharFrequency:
    if bcc_frequency is not None and bcc_frequency > 0:
        return ResolvedCharFrequency(int(bcc_frequency), bcc_source)
    synthetic = synthetic_frequency_from_unihan_columns(unihan_columns)
    return synthetic


def resolve_phrase_frequency(bcc_frequency: int | None) -> int:
    if bcc_frequency is not None and bcc_frequency > 0:
        return int(bcc_frequency)
    return PHRASE_LEXICON_DEFAULT_FREQUENCY


def resolve_phrase_frequencies_for_inventory(
    phrases: list[str],
    *,
    bcc_by_phrase: dict[str, int],
) -> dict[str, int]:
    resolved: dict[str, int] = {}
    for phrase in phrases:
        key = str(phrase or "").strip()
        if not key:
            continue
        resolved[key] = resolve_phrase_frequency(bcc_by_phrase.get(key))
    return resolved


def load_bcc_char_frequency_map(path: Path) -> tuple[dict[str, int], int]:
    if not path.exists():
        raise FileNotFoundError(f"frequency file not found: {path}")

    by_char: dict[str, int] = {}
    parsed_rows = 0
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            return {}, 0

        fieldnames = [name.strip() for name in reader.fieldnames]
        if len(fieldnames) < 2:
            raise ValueError(f"expected at least two CSV columns in {path}")

        key_field = fieldnames[0]
        freq_field = fieldnames[1]
        for row in reader:
            hanzi = str(row.get(key_field) or "").strip()
            freq_text = str(row.get(freq_field) or "").strip()
            if not hanzi or len(hanzi) != 1 or not freq_text:
                continue
            try:
                freq = int(freq_text)
            except ValueError:
                continue
            parsed_rows += 1
            previous = by_char.get(hanzi)
            if previous is None or freq > previous:
                by_char[hanzi] = freq
    return by_char, parsed_rows


def load_unihan_columns_by_hanzi(db_path: Path) -> dict[str, dict[str, str | None]]:
    if not db_path.exists():
        return {}

    conn = sqlite3.connect(db_path)
    try:
        if not _table_exists(conn, "unihan_readings_clean"):
            return {}

        column_sql = ", ".join(f"u.{column}" for column in UNIHAN_COLUMN_NAMES)
        query = f"""
            SELECT h.hanzi, {column_sql}
            FROM hanzi h
            LEFT JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
        """
        by_hanzi: dict[str, dict[str, str | None]] = {}
        for row in conn.execute(query):
            hanzi = str(row[0] or "").strip()
            if not hanzi:
                continue
            by_hanzi[hanzi] = {
                column: (str(row[index + 1]) if row[index + 1] is not None else None)
                for index, column in enumerate(UNIHAN_COLUMN_NAMES)
            }
        return by_hanzi
    finally:
        conn.close()


def load_unihan_columns_by_codepoint(db_path: Path) -> dict[str, dict[str, str | None]]:
    if not db_path.exists():
        return {}

    conn = sqlite3.connect(db_path)
    try:
        if not _table_exists(conn, "unihan_readings_clean"):
            return {}

        column_sql = ", ".join(f"u.{column}" for column in UNIHAN_COLUMN_NAMES)
        query = f"""
            SELECT h.codepoint, {column_sql}
            FROM hanzi h
            LEFT JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
        """
        by_codepoint: dict[str, dict[str, str | None]] = {}
        for row in conn.execute(query):
            codepoint = str(row[0] or "").strip()
            if not codepoint:
                continue
            by_codepoint[codepoint] = {
                column: (str(row[index + 1]) if row[index + 1] is not None else None)
                for index, column in enumerate(UNIHAN_COLUMN_NAMES)
            }
        return by_codepoint
    finally:
        conn.close()


def resolve_char_frequencies_for_hanzi(
    hanzi_values: list[str],
    *,
    bcc_by_hanzi: dict[str, int],
    unihan_by_hanzi: dict[str, dict[str, str | None]],
    bcc_source: str = BCC_SOURCE,
) -> dict[str, ResolvedCharFrequency]:
    resolved: dict[str, ResolvedCharFrequency] = {}
    for hanzi in hanzi_values:
        key = str(hanzi or "").strip()
        if not key:
            continue
        resolved[key] = resolve_char_frequency(
            bcc_frequency=bcc_by_hanzi.get(key),
            unihan_columns=unihan_by_hanzi.get(key),
            bcc_source=bcc_source,
        )
    return resolved


def build_hanzi_frequency_table(cur: sqlite3.Cursor) -> None:
    cur.execute("DROP TABLE IF EXISTS hanzi_frequency")
    cur.execute(
        """
        CREATE TABLE hanzi_frequency (
            codepoint         TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            frequency         INTEGER NOT NULL DEFAULT 0,
            frequency_source  TEXT NOT NULL DEFAULT 'synthetic/none'
        )
        """
    )
    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_hanzi_freq ON hanzi_frequency(frequency DESC)"
    )


def import_hanzi_frequency_rows(
    cur: sqlite3.Cursor,
    *,
    freq_path: Path,
    unihan_db_path: Path,
) -> tuple[int, int, int]:
    """Import effective frequencies for every row in hanzi.

    Returns (bcc_applied, synthetic_applied, skipped_file_keys).
    """
    bcc_by_hanzi, _parsed_rows = load_bcc_char_frequency_map(freq_path)
    unihan_by_codepoint = load_unihan_columns_by_codepoint(unihan_db_path)

    insert_rows: list[tuple[str, int, str]] = []
    bcc_applied = 0
    synthetic_applied = 0

    for hanzi, codepoint in cur.execute("SELECT hanzi, codepoint FROM hanzi"):
        resolved = resolve_char_frequency(
            bcc_frequency=bcc_by_hanzi.get(str(hanzi or "")),
            unihan_columns=unihan_by_codepoint.get(str(codepoint or "")),
        )
        if resolved.source == BCC_SOURCE:
            bcc_applied += 1
        elif resolved.frequency > 0:
            synthetic_applied += 1
        insert_rows.append((str(codepoint), resolved.frequency, resolved.source))

    if insert_rows:
        cur.executemany(
            """
            INSERT INTO hanzi_frequency (codepoint, frequency, frequency_source)
            VALUES (?, ?, ?)
            """,
            insert_rows,
        )

    skipped_file_keys = len(bcc_by_hanzi) - bcc_applied
    fill_zero_frequency_for_ling(cur)
    return bcc_applied, synthetic_applied, skipped_file_keys


def fill_zero_frequency_for_ling(cur: sqlite3.Cursor) -> int | None:
    row = cur.execute(
        """
        SELECT hf.frequency FROM hanzi_frequency hf
        JOIN hanzi h ON hf.codepoint = h.codepoint
        WHERE h.hanzi = ?
        """,
        (LING_HANZI,),
    ).fetchone()
    if row is None or int(row[0] or 0) != 0:
        return None

    placeholders = ",".join("?" for _ in DIGIT_HANZI)
    avg_row = cur.execute(
        f"""
        SELECT CAST(AVG(hf.frequency) AS INTEGER)
        FROM hanzi_frequency hf
        JOIN hanzi h ON hf.codepoint = h.codepoint
        WHERE h.hanzi IN ({placeholders})
        """,
        list(DIGIT_HANZI),
    ).fetchone()
    avg = int(avg_row[0] or 0)
    if avg <= 0:
        return None

    cur.execute(
        """
        UPDATE hanzi_frequency
        SET frequency = ?, frequency_source = 'supplement/ling_digit_average'
        WHERE codepoint = (SELECT codepoint FROM hanzi WHERE hanzi = ?)
        """,
        (avg, LING_HANZI),
    )
    return avg


def purge_legacy_frequency_metadata(conn: sqlite3.Connection) -> list[str]:
    cursor = conn.cursor()
    removed: list[str] = []
    for key in LEGACY_FREQUENCY_METADATA_KEYS:
        cursor.execute("DELETE FROM prototype_metadata WHERE key = ?", (key,))
        if cursor.rowcount:
            removed.append(key)
    return removed


def _table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
        (table_name,),
    ).fetchone()
    return row is not None
