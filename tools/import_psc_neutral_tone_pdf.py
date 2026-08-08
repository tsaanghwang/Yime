#!/usr/bin/env python3
"""Import the PSC mandatory-neutral-tone PDF into an existing audit database.

This importer deliberately uses the PDF text layer and vector table geometry.
It does not run OCR.  The source PDF is registered in ``documents`` while the
594-item list is kept in dedicated tables so that the already reviewed main
word-list entries and their review queue remain untouched.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


DATASET_KEY = "psc-2021-mandatory-neutral-tone"
DATASET_TITLE = "普通话水平测试用必读轻声词语表"
EXPECTED_PAGE_COUNTS = (100, 98, 100, 68, 65, 58, 63, 42)
WATERMARK_FRAGMENTS = frozenset({"畅", "言", "普", "通", "话", "A", "P", "APP"})


@dataclass(frozen=True)
class NeutralToneEntry:
    source_index: int
    page_number: int
    table_order: int
    row_order: int
    pair_order: int
    hanzi: str
    pinyin_raw: str
    pinyin_nfc: str
    raw_hanzi_cell: str
    raw_pinyin_cell: str
    evidence_json: str


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def strip_watermark_lines(value: str | None) -> str:
    """Remove only standalone watermark fragments inserted on separate lines."""

    parts = [part.strip() for part in (value or "").splitlines() if part.strip()]
    return "".join(part for part in parts if part not in WATERMARK_FRAGMENTS)


def normalize_hanzi(value: str | None) -> str:
    cleaned = strip_watermark_lines(value)
    return unicodedata.normalize("NFC", "".join(cleaned.split()))


def normalize_pinyin(value: str | None) -> tuple[str, str]:
    raw = strip_watermark_lines(value)
    normalized = unicodedata.normalize("NFC", unicodedata.normalize("NFKC", raw))
    return raw, "".join(normalized.split())


def has_cjk(value: str) -> bool:
    return any(
        0x3400 <= ord(char) <= 0x9FFF or 0x20000 <= ord(char) <= 0x323AF
        for char in value
    )


def has_latin(value: str) -> bool:
    decomposed = unicodedata.normalize("NFKD", value)
    return any("a" <= char.lower() <= "z" for char in decomposed)


def pinyin_characters_are_valid(value: str) -> bool:
    for char in value:
        if char in "()'·:-/":
            continue
        category = unicodedata.category(char)
        if category.startswith("L") or category.startswith("M"):
            continue
        return False
    return True


def bbox_json(bbox: Sequence[float] | None) -> list[float] | None:
    if bbox is None:
        return None
    return [round(float(value), 3) for value in bbox]


def extract_entries(source_pdf: Path) -> tuple[list[NeutralToneEntry], list[int]]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover - environment diagnostic
        raise RuntimeError("pdfplumber is required for direct PDF extraction") from exc

    entries: list[NeutralToneEntry] = []
    page_counts: list[int] = []
    source_index = 0

    with pdfplumber.open(source_pdf) as pdf:
        if len(pdf.pages) != len(EXPECTED_PAGE_COUNTS):
            raise ValueError(
                f"expected {len(EXPECTED_PAGE_COUNTS)} pages, found {len(pdf.pages)}"
            )

        for page_number, page in enumerate(pdf.pages, start=1):
            page_start = len(entries)
            tables = page.find_tables()
            if not tables:
                raise ValueError(f"page {page_number} contains no vector tables")

            for table_order, table in enumerate(tables, start=1):
                extracted_rows = table.extract()
                if len(extracted_rows) != len(table.rows):
                    raise ValueError(
                        f"page {page_number} table {table_order}: row geometry mismatch"
                    )

                for row_order, (values, row_geometry) in enumerate(
                    zip(extracted_rows, table.rows), start=1
                ):
                    values = list(values or [])
                    cells = list(row_geometry.cells)
                    if len(values) != len(cells) or len(values) % 2:
                        raise ValueError(
                            f"page {page_number} table {table_order} row {row_order}: "
                            f"expected paired cells, found {len(values)}"
                        )

                    for cell_index in range(0, len(values), 2):
                        raw_hanzi = values[cell_index] or ""
                        raw_pinyin = values[cell_index + 1] or ""
                        hanzi = normalize_hanzi(raw_hanzi)
                        pinyin_raw, pinyin_nfc = normalize_pinyin(raw_pinyin)
                        if not hanzi and not pinyin_nfc:
                            continue
                        if not hanzi or not pinyin_nfc:
                            raise ValueError(
                                f"page {page_number} table {table_order} row {row_order} "
                                f"pair {cell_index // 2 + 1}: incomplete pair "
                                f"{raw_hanzi!r} / {raw_pinyin!r}"
                            )

                        source_index += 1
                        evidence = {
                            "page_bbox": bbox_json(page.bbox),
                            "table_bbox": bbox_json(table.bbox),
                            "hanzi_bbox": bbox_json(cells[cell_index]),
                            "pinyin_bbox": bbox_json(cells[cell_index + 1]),
                        }
                        entries.append(
                            NeutralToneEntry(
                                source_index=source_index,
                                page_number=page_number,
                                table_order=table_order,
                                row_order=row_order,
                                pair_order=cell_index // 2 + 1,
                                hanzi=hanzi,
                                pinyin_raw=pinyin_raw,
                                pinyin_nfc=pinyin_nfc,
                                raw_hanzi_cell=raw_hanzi,
                                raw_pinyin_cell=raw_pinyin,
                                evidence_json=json_text(evidence),
                            )
                        )

            page_counts.append(len(entries) - page_start)

    return entries, page_counts


def validate_entries(
    entries: Sequence[NeutralToneEntry],
    page_counts: Sequence[int],
    expected_count: int,
) -> dict[str, Any]:
    errors: list[str] = []
    if len(entries) != expected_count:
        errors.append(f"expected {expected_count} entries, found {len(entries)}")
    if tuple(page_counts) != EXPECTED_PAGE_COUNTS:
        errors.append(
            f"page counts differ: expected {EXPECTED_PAGE_COUNTS}, found {tuple(page_counts)}"
        )

    for expected_index, entry in enumerate(entries, start=1):
        if entry.source_index != expected_index:
            errors.append(
                f"source index discontinuity at {expected_index}: {entry.source_index}"
            )
        if not has_cjk(entry.hanzi):
            errors.append(f"entry {entry.source_index}: no CJK text in {entry.hanzi!r}")
        if any(fragment in entry.hanzi for fragment in WATERMARK_FRAGMENTS):
            # Single-character fragments can be legitimate inside words, so only raw
            # newline fragments are removed.  This check catches standalone leftovers.
            if entry.hanzi in WATERMARK_FRAGMENTS:
                errors.append(
                    f"entry {entry.source_index}: watermark-only Han field {entry.hanzi!r}"
                )
        if not has_latin(entry.pinyin_nfc):
            errors.append(
                f"entry {entry.source_index}: no Latin pinyin in {entry.pinyin_nfc!r}"
            )
        if not pinyin_characters_are_valid(entry.pinyin_nfc):
            errors.append(
                f"entry {entry.source_index}: unexpected pinyin character in "
                f"{entry.pinyin_nfc!r}"
            )
        if "\ufffd" in entry.hanzi + entry.pinyin_nfc:
            errors.append(f"entry {entry.source_index}: replacement character present")

    exact_pairs: dict[tuple[str, str], list[int]] = {}
    hanzi_readings: dict[str, set[str]] = {}
    for entry in entries:
        exact_pairs.setdefault((entry.hanzi, entry.pinyin_nfc), []).append(
            entry.source_index
        )
        hanzi_readings.setdefault(entry.hanzi, set()).add(entry.pinyin_nfc)
    duplicate_pairs = {
        pair: indexes for pair, indexes in exact_pairs.items() if len(indexes) > 1
    }
    if duplicate_pairs:
        errors.append(f"exact duplicate pairs found: {duplicate_pairs}")

    if errors:
        raise ValueError("neutral-tone quality gate failed:\n- " + "\n- ".join(errors))

    return {
        "entry_count": len(entries),
        "page_counts": list(page_counts),
        "exact_duplicate_pairs": 0,
        "hanzi_with_multiple_readings": sum(
            1 for readings in hanzi_readings.values() if len(readings) > 1
        ),
    }


def require_core_schema(conn: sqlite3.Connection) -> None:
    required = {"documents", "pages", "entries", "issues"}
    actual = {
        str(row[0])
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    missing = required - actual
    if missing:
        raise ValueError(f"database is missing core tables: {sorted(missing)}")


def ensure_neutral_tone_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS neutral_tone_datasets (
            id INTEGER PRIMARY KEY,
            dataset_key TEXT NOT NULL UNIQUE,
            document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            expected_entry_count INTEGER NOT NULL,
            imported_entry_count INTEGER NOT NULL,
            extraction_method TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            imported_utc TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS neutral_tone_entries (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES neutral_tone_datasets(id) ON DELETE CASCADE,
            source_index INTEGER NOT NULL,
            page_number INTEGER NOT NULL,
            table_order INTEGER NOT NULL,
            row_order INTEGER NOT NULL,
            pair_order INTEGER NOT NULL,
            hanzi TEXT NOT NULL,
            pinyin_raw TEXT NOT NULL,
            pinyin_nfc TEXT NOT NULL,
            raw_hanzi_cell TEXT NOT NULL,
            raw_pinyin_cell TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            UNIQUE(dataset_id, source_index),
            UNIQUE(dataset_id, page_number, table_order, row_order, pair_order)
        );

        CREATE INDEX IF NOT EXISTS idx_neutral_tone_entries_hanzi
            ON neutral_tone_entries(hanzi);
        CREATE INDEX IF NOT EXISTS idx_neutral_tone_entries_pinyin
            ON neutral_tone_entries(pinyin_nfc);

        CREATE VIEW IF NOT EXISTS neutral_tone_list AS
        SELECT e.source_index, e.hanzi, e.pinyin_nfc AS pinyin,
               e.page_number, e.table_order, e.row_order, e.pair_order
          FROM neutral_tone_entries AS e
          JOIN neutral_tone_datasets AS d ON d.id=e.dataset_id
         WHERE d.dataset_key='psc-2021-mandatory-neutral-tone'
         ORDER BY e.source_index;
        """
    )


def table_counts(conn: sqlite3.Connection) -> dict[str, int]:
    result: dict[str, int] = {}
    for table in ("entries", "issues", "manual_corrections", "manual_review_history"):
        exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
        ).fetchone()
        result[table] = (
            int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
            if exists
            else 0
        )
    return result


def make_backup(database: Path) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    target = database.with_name(
        f"{database.stem}.before_neutral_tone_import.{stamp}{database.suffix}"
    )
    source_conn = sqlite3.connect(database)
    target_conn = sqlite3.connect(target)
    try:
        source_conn.backup(target_conn)
    finally:
        target_conn.close()
        source_conn.close()
    return target


def import_entries(
    database: Path,
    source_pdf: Path,
    entries: Sequence[NeutralToneEntry],
    page_counts: Sequence[int],
    expected_count: int,
) -> dict[str, Any]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required") from exc

    conn = sqlite3.connect(database, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=30000")
    before = table_counts(conn)
    source_hash = sha256_file(source_pdf)
    now = utc_now()
    try:
        require_core_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        ensure_neutral_tone_schema(conn)

        document = conn.execute(
            "SELECT id FROM documents WHERE source_sha256=?", (source_hash,)
        ).fetchone()
        if document:
            document_id = int(document["id"])
            conn.execute(
                """
                UPDATE documents
                   SET source_path=?, source_filename=?, source_size=?, page_count=?,
                       updated_utc=?, ocr_engine=?, ocr_version=?, detection_model=?,
                       recognition_model=?, language=?
                 WHERE id=?
                """,
                (
                    str(source_pdf.resolve()),
                    source_pdf.name,
                    source_pdf.stat().st_size,
                    len(page_counts),
                    now,
                    "PDF text layer",
                    pdfplumber.__version__,
                    "vector table lines",
                    "embedded Unicode text",
                    "zh-Latn-pinyin",
                    document_id,
                ),
            )
        else:
            cursor = conn.execute(
                """
                INSERT INTO documents(
                    source_path, source_filename, source_sha256, source_size,
                    page_count, created_utc, updated_utc, ocr_engine, ocr_version,
                    detection_model, recognition_model, language
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    str(source_pdf.resolve()),
                    source_pdf.name,
                    source_hash,
                    source_pdf.stat().st_size,
                    len(page_counts),
                    now,
                    now,
                    "PDF text layer",
                    pdfplumber.__version__,
                    "vector table lines",
                    "embedded Unicode text",
                    "zh-Latn-pinyin",
                ),
            )
            document_id = int(cursor.lastrowid)

        conn.execute("DELETE FROM pages WHERE document_id=?", (document_id,))
        for page_number, entry_count in enumerate(page_counts, start=1):
            conn.execute(
                """
                INSERT INTO pages(
                    document_id, page_number, image_width, image_height, status,
                    span_count, entry_count, ocr_json, updated_utc
                ) VALUES(?,?,?,?,?,?,?,?,?)
                """,
                (
                    document_id,
                    page_number,
                    None,
                    None,
                    "text_extracted",
                    entry_count * 2,
                    entry_count,
                    json_text(
                        {
                            "method": "pdfplumber vector-table extraction",
                            "entry_count": entry_count,
                        }
                    ),
                    now,
                ),
            )

        dataset = conn.execute(
            "SELECT id FROM neutral_tone_datasets WHERE dataset_key=?",
            (DATASET_KEY,),
        ).fetchone()
        if dataset:
            dataset_id = int(dataset["id"])
            conn.execute(
                """
                UPDATE neutral_tone_datasets
                   SET document_id=?, title=?, expected_entry_count=?,
                       imported_entry_count=?, extraction_method=?,
                       extraction_version=1, imported_utc=?
                 WHERE id=?
                """,
                (
                    document_id,
                    DATASET_TITLE,
                    expected_count,
                    len(entries),
                    "pdfplumber text layer and vector tables",
                    now,
                    dataset_id,
                ),
            )
            conn.execute(
                "DELETE FROM neutral_tone_entries WHERE dataset_id=?", (dataset_id,)
            )
        else:
            cursor = conn.execute(
                """
                INSERT INTO neutral_tone_datasets(
                    dataset_key, document_id, title, expected_entry_count,
                    imported_entry_count, extraction_method, extraction_version,
                    imported_utc
                ) VALUES(?,?,?,?,?,?,1,?)
                """,
                (
                    DATASET_KEY,
                    document_id,
                    DATASET_TITLE,
                    expected_count,
                    len(entries),
                    "pdfplumber text layer and vector tables",
                    now,
                ),
            )
            dataset_id = int(cursor.lastrowid)

        conn.executemany(
            """
            INSERT INTO neutral_tone_entries(
                dataset_id, source_index, page_number, table_order, row_order,
                pair_order, hanzi, pinyin_raw, pinyin_nfc, raw_hanzi_cell,
                raw_pinyin_cell, evidence_json
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                (
                    dataset_id,
                    entry.source_index,
                    entry.page_number,
                    entry.table_order,
                    entry.row_order,
                    entry.pair_order,
                    entry.hanzi,
                    entry.pinyin_raw,
                    entry.pinyin_nfc,
                    entry.raw_hanzi_cell,
                    entry.raw_pinyin_cell,
                    entry.evidence_json,
                )
                for entry in entries
            ),
        )
        conn.execute(
            "INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)",
            ("neutral_tone_dataset_schema_version", "1"),
        )

        after = table_counts(conn)
        if after != before:
            raise RuntimeError(
                f"protected main/review table counts changed: before={before}, after={after}"
            )
        stored_count = int(
            conn.execute(
                "SELECT COUNT(*) FROM neutral_tone_entries WHERE dataset_id=?",
                (dataset_id,),
            ).fetchone()[0]
        )
        if stored_count != expected_count:
            raise RuntimeError(
                f"stored entry count differs: expected {expected_count}, found {stored_count}"
            )
        conn.commit()
        return {
            "document_id": document_id,
            "dataset_id": dataset_id,
            "stored_count": stored_count,
            "protected_counts": after,
            "source_sha256": source_hash,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_pdf", type=Path)
    parser.add_argument("database", type=Path)
    parser.add_argument("--expected-count", type=int, default=594)
    parser.add_argument(
        "--write",
        action="store_true",
        help="back up and update the database; without this flag parsing is read-only",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    source_pdf = args.source_pdf.resolve()
    database = args.database.resolve()
    if not source_pdf.is_file():
        raise FileNotFoundError(source_pdf)
    if not database.is_file():
        raise FileNotFoundError(database)

    entries, page_counts = extract_entries(source_pdf)
    summary = validate_entries(entries, page_counts, args.expected_count)
    output: dict[str, Any] = {
        "mode": "write" if args.write else "dry-run",
        "source_pdf": str(source_pdf),
        "source_sha256": sha256_file(source_pdf),
        **summary,
    }
    if args.write:
        backup = make_backup(database)
        output["backup"] = str(backup)
        output.update(
            import_entries(
                database,
                source_pdf,
                entries,
                page_counts,
                args.expected_count,
            )
        )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
