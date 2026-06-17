"""Shared helpers for mandarin_readings_corrections table and txt I/O."""

from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from pinyin_match import split_clean_readings

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DB_PATH = SCRIPT_DIR / "unihan_readings.db"
DEFAULT_CORRECTIONS_FILE = SCRIPT_DIR / "mandarin_readings_corrections.txt"

CORRECTIONS_DDL = """
    CREATE TABLE IF NOT EXISTS mandarin_readings_corrections (
        codepoint               TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
        hanzi                   TEXT NOT NULL,
        readings                TEXT NOT NULL,
        common_reading          TEXT,
        common_reading_source   TEXT,
        review_status           TEXT NOT NULL DEFAULT 'pending',
        diff_origin             TEXT,
        note                    TEXT
    )
"""

STATUS_RE = re.compile(r"status=(pending|approved|rejected)", re.I)
ORIGIN_RE = re.compile(r"origin=([^\s|]+)", re.I)
COMMON_RE = re.compile(r"common=([^\s|]+)", re.I)
SOURCE_RE = re.compile(r"source=([^\s|]+)", re.I)


@dataclass(frozen=True)
class CorrectionRow:
    codepoint: str
    hanzi: str
    readings: str
    common_reading: str | None
    common_reading_source: str | None
    review_status: str
    diff_origin: str | None
    note: str | None


def ensure_corrections_table(cur: sqlite3.Cursor) -> None:
    cur.execute(CORRECTIONS_DDL)
    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_mandarin_corrections_status "
        "ON mandarin_readings_corrections(review_status)"
    )


def _parse_comment_fields(comment: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    if not comment:
        return fields
    parts = [part.strip() for part in comment.split("|") if part.strip()]
    if parts:
        fields["hanzi"] = parts[0]
    for part in parts[1:]:
        for key, regex in (
            ("review_status", STATUS_RE),
            ("diff_origin", ORIGIN_RE),
            ("common_reading", COMMON_RE),
            ("common_reading_source", SOURCE_RE),
        ):
            match = regex.search(part)
            if match:
                fields[key] = match.group(1)
    return fields


def parse_corrections_line(line: str) -> CorrectionRow | None:
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    if ":" not in line:
        return None
    head, _, comment = line.partition("#")
    codepoint, _, readings_part = head.partition(":")
    codepoint = codepoint.strip()
    readings = readings_part.strip()
    if not codepoint.startswith("U+"):
        return None
    fields = _parse_comment_fields(comment.strip())
    hanzi = fields.get("hanzi", "")
    if not hanzi:
        return None
    status = fields.get("review_status", "pending").lower()
    if status not in {"pending", "approved", "rejected"}:
        status = "pending"
    return CorrectionRow(
        codepoint=codepoint,
        hanzi=hanzi,
        readings=readings,
        common_reading=fields.get("common_reading"),
        common_reading_source=fields.get("common_reading_source"),
        review_status=status,
        diff_origin=fields.get("diff_origin"),
        note=None,
    )


def parse_corrections_file(path: Path) -> list[CorrectionRow]:
    rows: list[CorrectionRow] = []
    pending_note: str | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("# note:"):
            pending_note = line.split(":", 1)[1].strip()
            continue
        if line.startswith("#"):
            continue
        parsed = parse_corrections_line(line)
        if parsed is None:
            pending_note = None
            continue
        rows.append(
            CorrectionRow(
                codepoint=parsed.codepoint,
                hanzi=parsed.hanzi,
                readings=parsed.readings,
                common_reading=parsed.common_reading,
                common_reading_source=parsed.common_reading_source,
                review_status=parsed.review_status,
                diff_origin=parsed.diff_origin,
                note=pending_note,
            )
        )
        pending_note = None
    return rows


def load_corrections_from_db(conn: sqlite3.Connection) -> list[CorrectionRow]:
    rows = conn.execute(
        "SELECT codepoint, hanzi, readings, common_reading, common_reading_source, "
        "review_status, diff_origin, note FROM mandarin_readings_corrections "
        "ORDER BY codepoint"
    ).fetchall()
    return [
        CorrectionRow(
            codepoint=row[0],
            hanzi=row[1],
            readings=row[2],
            common_reading=row[3],
            common_reading_source=row[4],
            review_status=row[5],
            diff_origin=row[6],
            note=row[7],
        )
        for row in rows
    ]


def import_corrections_file(conn: sqlite3.Connection, path: Path) -> int:
    ensure_corrections_table(conn.cursor())
    rows = parse_corrections_file(path)
    for row in rows:
        conn.execute(
            "INSERT INTO mandarin_readings_corrections "
            "(codepoint, hanzi, readings, common_reading, common_reading_source, "
            "review_status, diff_origin, note) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(codepoint) DO UPDATE SET "
            "hanzi=excluded.hanzi, readings=excluded.readings, "
            "common_reading=excluded.common_reading, "
            "common_reading_source=excluded.common_reading_source, "
            "review_status=excluded.review_status, diff_origin=excluded.diff_origin, "
            "note=excluded.note",
            (
                row.codepoint,
                row.hanzi,
                row.readings,
                row.common_reading,
                row.common_reading_source,
                row.review_status,
                row.diff_origin,
                row.note,
            ),
        )
    return len(rows)


def export_corrections_file(conn: sqlite3.Connection, path: Path) -> int:
    rows = load_corrections_from_db(conn)
    lines = [
        "# mandarin_readings_corrections.txt",
        "# 格式: U+XXXX: reading1,reading2  # 汉字 | status=pending|approved|rejected | origin=manual",
        "# 可选上下文行（紧挨数据行之前）: # note: ...（Unihan 各列 / 辞书 / 规范字表）",
        "# 仅 status=approved 会在构建时覆盖 mandarin_readings_merged",
        "",
    ]
    for row in rows:
        if row.note:
            lines.append(f"# note: {row.note}")
        meta = [f"status={row.review_status}"]
        if row.diff_origin:
            meta.append(f"origin={row.diff_origin}")
        if row.common_reading:
            meta.append(f"common={row.common_reading}")
        if row.common_reading_source:
            meta.append(f"source={row.common_reading_source}")
        lines.append(
            f"{row.codepoint}: {row.readings}  # {row.hanzi} | {' | '.join(meta)}"
        )
        lines.append("")
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return len(rows)


def resolve_common_reading(
    readings: str,
    common_reading: str | None,
    fallback_common: str | None,
) -> tuple[str, str]:
    candidates = split_clean_readings(readings)
    if not candidates:
        return "", "correction"
    if common_reading and common_reading in candidates:
        return common_reading, "correction"
    if fallback_common and fallback_common in candidates:
        return fallback_common, "correction"
    return candidates[0], "correction"


def apply_approved_corrections(conn: sqlite3.Connection) -> int:
    ensure_corrections_table(conn.cursor())
    rows = conn.execute(
        "SELECT c.codepoint, c.readings, c.common_reading, c.common_reading_source, "
        "m.common_reading "
        "FROM mandarin_readings_corrections c "
        "INNER JOIN mandarin_readings_merged m ON c.codepoint = m.codepoint "
        "WHERE c.review_status = 'approved'"
    ).fetchall()
    applied = 0
    for codepoint, readings, common, source, merged_common in rows:
        common_reading, default_source = resolve_common_reading(
            readings,
            common,
            merged_common,
        )
        common_source = source or default_source
        is_single = 1 if len(split_clean_readings(readings)) <= 1 else 0
        conn.execute(
            "UPDATE mandarin_readings_merged "
            "SET readings = ?, common_reading = ?, common_reading_source = ?, is_single = ? "
            "WHERE codepoint = ?",
            (readings, common_reading, common_source, is_single, codepoint),
        )
        applied += 1
    return applied


def create_correction_views(cur: sqlite3.Cursor) -> None:
    cur.execute("DROP VIEW IF EXISTS view_mandarin_readings_corrections_pending")
    cur.execute("DROP VIEW IF EXISTS view_mandarin_readings_corrections_approved")
    cur.execute("""
        CREATE VIEW view_mandarin_readings_corrections_pending AS
        SELECT codepoint, hanzi, readings, common_reading, common_reading_source,
               review_status, diff_origin, note
        FROM mandarin_readings_corrections
        WHERE review_status = 'pending'
        ORDER BY codepoint
    """)
    cur.execute("""
        CREATE VIEW view_mandarin_readings_corrections_approved AS
        SELECT codepoint, hanzi, readings, common_reading, common_reading_source,
               review_status, diff_origin, note
        FROM mandarin_readings_corrections
        WHERE review_status = 'approved'
        ORDER BY codepoint
    """)
