#!/usr/bin/env python3
"""Import artifact-tool extracted PSC rare/difficult words into SQLite.

The XLSX is the structured source.  The original PDF is independently parsed
and compared item-for-item after known watermark fragments are removed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from import_psc_neutral_tone_pdf import (
    has_cjk,
    has_latin,
    json_text,
    normalize_hanzi,
    normalize_pinyin,
    require_core_schema,
    sha256_file,
    strip_watermark_lines,
    utc_now,
)


DATASET_KEY = "psc-2021-rare-difficult-words"
DATASET_TITLE = "普通话水平测试生僻字难点字词"
EXPECTED_SHEETS = ("Table 1", "Table 2")
EXPECTED_SHEET_COUNTS = (171, 107)
EXPECTED_GROUPS = (
    "b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "q",
    "r", "s", "t", "x", "z", "零声母",
)
EXPECTED_ENTRY_COUNT = 278
WATERMARK_CHARACTERS = frozenset("畅言普通话AP")


@dataclass(frozen=True)
class RareWordGroup:
    source_index: int
    sheet_name: str
    source_row: int
    source_cell: str
    group_label: str


@dataclass(frozen=True)
class RareWordEntry:
    source_index: int
    group_source_index: int
    sheet_name: str
    source_row: int
    pair_order: int
    hanzi_cell: str
    pinyin_cell: str
    hanzi: str
    pinyin_raw: str
    pinyin_nfc: str
    raw_hanzi_cell: str
    raw_pinyin_cell: str


def excel_column_number(label: str) -> int:
    result = 0
    for char in label.upper():
        if not "A" <= char <= "Z":
            raise ValueError(f"invalid Excel column label: {label!r}")
        result = result * 26 + ord(char) - ord("A") + 1
    return result


def excel_column_label(number: int) -> str:
    if number < 1:
        raise ValueError(number)
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(ord("A") + remainder) + result
    return result


def range_origin(address: str) -> tuple[int, int]:
    match = re.fullmatch(r"([A-Za-z]+)(\d+):([A-Za-z]+)(\d+)", address)
    if not match:
        raise ValueError(f"unsupported used-range address: {address!r}")
    return excel_column_number(match.group(1)), int(match.group(2))


def normalize_text(value: Any) -> str:
    return "".join(unicodedata.normalize("NFC", str(value or "")).split())


def normalize_rare_pinyin(value: Any) -> tuple[str, str]:
    raw = normalize_text(value)
    normalized = unicodedata.normalize("NFC", unicodedata.normalize("NFKC", raw))
    return raw, normalized


def parse_workbook_json(
    extracted_json: Path,
) -> tuple[list[RareWordGroup], list[RareWordEntry], list[int], dict[str, Any]]:
    payload = json.loads(extracted_json.read_text(encoding="utf-8"))
    if "sheets" in payload:
        sheets = payload["sheets"]
        metadata = {key: value for key, value in payload.items() if key != "sheets"}
    else:
        # Backward-compatible with the inspection JSON produced during this import.
        sheets = payload
        metadata = {}

    if tuple(sheets) != EXPECTED_SHEETS:
        raise ValueError(f"expected sheets {EXPECTED_SHEETS}, found {tuple(sheets)}")

    groups: list[RareWordGroup] = []
    entries: list[RareWordEntry] = []
    sheet_counts: list[int] = []

    for sheet_name, sheet_payload in sheets.items():
        address = str(sheet_payload["address"])
        values = list(sheet_payload["values"])
        start_column, start_row = range_origin(address)
        sheet_start = len(entries)
        current_group: RareWordGroup | None = None

        for relative_row, raw_row in enumerate(values):
            source_row = start_row + relative_row
            row = list(raw_row or [])
            if len(row) % 2:
                raise ValueError(f"{sheet_name}!{source_row}: odd number of cells")
            cleaned = [normalize_text(value) for value in row]
            nonempty = [(index, value) for index, value in enumerate(cleaned) if value]

            if len(nonempty) == 1 and nonempty[0][0] == 0:
                current_group = RareWordGroup(
                    source_index=len(groups) + 1,
                    sheet_name=sheet_name,
                    source_row=source_row,
                    source_cell=f"{excel_column_label(start_column)}{source_row}",
                    group_label=nonempty[0][1],
                )
                groups.append(current_group)
                continue
            if current_group is None and nonempty:
                raise ValueError(f"{sheet_name}!{source_row}: entry precedes group")

            for cell_index in range(0, len(row), 2):
                raw_hanzi = "" if row[cell_index] is None else str(row[cell_index])
                raw_pinyin = "" if row[cell_index + 1] is None else str(row[cell_index + 1])
                hanzi = normalize_hanzi(raw_hanzi)
                pinyin_raw, pinyin_nfc = normalize_rare_pinyin(raw_pinyin)
                if not hanzi and not pinyin_nfc:
                    continue
                if not hanzi or not pinyin_nfc:
                    raise ValueError(
                        f"{sheet_name}!{source_row} pair {cell_index // 2 + 1}: "
                        f"incomplete {raw_hanzi!r} / {raw_pinyin!r}"
                    )
                assert current_group is not None
                hanzi_col = start_column + cell_index
                pinyin_col = hanzi_col + 1
                entries.append(
                    RareWordEntry(
                        source_index=len(entries) + 1,
                        group_source_index=current_group.source_index,
                        sheet_name=sheet_name,
                        source_row=source_row,
                        pair_order=cell_index // 2 + 1,
                        hanzi_cell=f"{excel_column_label(hanzi_col)}{source_row}",
                        pinyin_cell=f"{excel_column_label(pinyin_col)}{source_row}",
                        hanzi=hanzi,
                        pinyin_raw=pinyin_raw,
                        pinyin_nfc=pinyin_nfc,
                        raw_hanzi_cell=raw_hanzi,
                        raw_pinyin_cell=raw_pinyin,
                    )
                )
        sheet_counts.append(len(entries) - sheet_start)

    return groups, entries, sheet_counts, metadata


def pinyin_characters_are_valid(value: str) -> bool:
    allowed = {"/", "'", chr(0x2019), chr(0x00B7), ":", "-"}
    for char in value:
        category = unicodedata.category(char)
        if char in allowed or category.startswith("L") or category.startswith("M"):
            continue
        return False
    return True


def validate_workbook_entries(
    groups: Sequence[RareWordGroup],
    entries: Sequence[RareWordEntry],
    sheet_counts: Sequence[int],
) -> dict[str, Any]:
    errors: list[str] = []
    if tuple(group.group_label for group in groups) != EXPECTED_GROUPS:
        errors.append("group labels/order differ from the expected 19 groups")
    if len(entries) != EXPECTED_ENTRY_COUNT:
        errors.append(f"expected {EXPECTED_ENTRY_COUNT} entries, found {len(entries)}")
    if tuple(sheet_counts) != EXPECTED_SHEET_COUNTS:
        errors.append(
            f"expected sheet counts {EXPECTED_SHEET_COUNTS}, found {tuple(sheet_counts)}"
        )

    valid_group_indexes = {group.source_index for group in groups}
    group_counts = {index: 0 for index in valid_group_indexes}
    exact_pairs: dict[tuple[str, str], list[int]] = {}
    for expected_index, entry in enumerate(entries, start=1):
        if entry.source_index != expected_index:
            errors.append(f"entry index discontinuity at {expected_index}")
        if entry.group_source_index not in valid_group_indexes:
            errors.append(f"entry {entry.source_index}: unknown group")
        else:
            group_counts[entry.group_source_index] += 1
        if not has_cjk(entry.hanzi):
            errors.append(f"entry {entry.source_index}: invalid Han text {entry.hanzi!r}")
        if not has_latin(entry.pinyin_nfc):
            errors.append(
                f"entry {entry.source_index}: invalid pinyin {entry.pinyin_nfc!r}"
            )
        if not pinyin_characters_are_valid(entry.pinyin_nfc):
            errors.append(
                f"entry {entry.source_index}: unexpected pinyin character in "
                f"{entry.pinyin_nfc!r}"
            )
        if "\ufffd" in entry.hanzi + entry.pinyin_nfc:
            errors.append(f"entry {entry.source_index}: replacement character present")
        exact_pairs.setdefault((entry.hanzi, entry.pinyin_nfc), []).append(
            entry.source_index
        )

    empty_groups = [index for index, count in group_counts.items() if count == 0]
    if empty_groups:
        errors.append(f"groups contain no entries: {empty_groups}")
    duplicate_pairs = {
        pair: indexes for pair, indexes in exact_pairs.items() if len(indexes) > 1
    }
    if duplicate_pairs:
        errors.append(f"exact duplicate pairs found: {duplicate_pairs}")
    if errors:
        raise ValueError("rare-word quality gate failed:\n- " + "\n- ".join(errors))

    return {
        "entry_count": len(entries),
        "group_count": len(groups),
        "sheet_counts": list(sheet_counts),
        "exact_duplicate_pairs": 0,
        "multiple_pronunciation_entries": sum(
            1 for entry in entries if "/" in entry.pinyin_nfc
        ),
    }


def clean_pdf_heading(value: str | None) -> str:
    normalized = "".join(
        unicodedata.normalize("NFKC", strip_watermark_lines(value)).split()
    )
    return "".join(char for char in normalized if char not in WATERMARK_CHARACTERS)


def clean_pdf_data_field(value: str | None, is_hanzi: bool) -> tuple[str, bool]:
    if is_hanzi:
        cleaned = normalize_hanzi(value)
        validator = has_cjk
    else:
        _, cleaned = normalize_pinyin(value)
        validator = has_latin
    original = cleaned
    while len(cleaned) > 1 and cleaned[0] in {"A", "P"} and validator(cleaned[1:]):
        cleaned = cleaned[1:]
    while len(cleaned) > 1 and cleaned[-1] in {"A", "P"} and validator(cleaned[:-1]):
        cleaned = cleaned[:-1]
    return cleaned, cleaned != original


def parse_pdf_reference(
    reference_pdf: Path,
) -> tuple[list[str], list[tuple[str, str, str]], list[int], int]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required for PDF validation") from exc

    groups: list[str] = []
    entries: list[tuple[str, str, str]] = []
    page_counts: list[int] = []
    artifact_corrections = 0
    current_group = ""

    with pdfplumber.open(reference_pdf) as pdf:
        if len(pdf.pages) != len(EXPECTED_SHEET_COUNTS):
            raise ValueError(f"reference PDF page count differs: {len(pdf.pages)}")
        for page_number, page in enumerate(pdf.pages, start=1):
            page_start = len(entries)
            tables = page.find_tables()
            if len(tables) != 1:
                raise ValueError(
                    f"reference PDF page {page_number}: expected one table"
                )
            for row_number, raw_row in enumerate(tables[0].extract(), start=1):
                row = list(raw_row or [])
                if len(row) % 2:
                    raise ValueError(
                        f"reference PDF page {page_number} row {row_number}: odd cells"
                    )
                complete: list[tuple[str, str]] = []
                residues: list[tuple[str, str]] = []
                for index in range(0, len(row), 2):
                    hanzi, hanzi_changed = clean_pdf_data_field(row[index], True)
                    pinyin, pinyin_changed = clean_pdf_data_field(row[index + 1], False)
                    artifact_corrections += int(hanzi_changed) + int(pinyin_changed)
                    if hanzi and pinyin:
                        complete.append((hanzi, pinyin))
                    elif hanzi or pinyin:
                        residues.append((row[index] or "", row[index + 1] or ""))

                if not complete:
                    candidates = [clean_pdf_heading(hanzi) for hanzi, pinyin in residues if not pinyin]
                    candidates = [candidate for candidate in candidates if candidate]
                    if candidates:
                        if len(candidates) != 1:
                            raise ValueError(
                                f"reference PDF page {page_number} row {row_number}: "
                                f"ambiguous headings {candidates}"
                            )
                        current_group = candidates[0]
                        groups.append(current_group)
                    continue
                if not current_group:
                    raise ValueError("reference PDF entry precedes group")
                for hanzi, pinyin in complete:
                    entries.append((current_group, hanzi, pinyin))
            page_counts.append(len(entries) - page_start)
    return groups, entries, page_counts, artifact_corrections


def validate_against_pdf(
    groups: Sequence[RareWordGroup],
    entries: Sequence[RareWordEntry],
    reference_pdf: Path,
) -> dict[str, Any]:
    pdf_groups, pdf_entries, page_counts, corrections = parse_pdf_reference(
        reference_pdf
    )
    workbook_groups = [group.group_label for group in groups]
    workbook_entries = [
        (workbook_groups[entry.group_source_index - 1], entry.hanzi, entry.pinyin_nfc)
        for entry in entries
    ]
    if workbook_groups != pdf_groups:
        raise ValueError("XLSX group list differs from the reference PDF")
    if workbook_entries != pdf_entries:
        differences = [
            (index, workbook, pdf)
            for index, (workbook, pdf) in enumerate(
                zip(workbook_entries, pdf_entries), start=1
            )
            if workbook != pdf
        ]
        raise ValueError(
            f"XLSX differs from reference PDF in {len(differences)} entries: "
            f"{differences[:10]}"
        )
    return {
        "reference_pdf_equal": True,
        "reference_page_counts": page_counts,
        "pdf_watermark_cell_corrections": corrections,
    }


def ensure_rare_word_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS rare_word_datasets (
            id INTEGER PRIMARY KEY,
            dataset_key TEXT NOT NULL UNIQUE,
            workbook_document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE CASCADE,
            reference_document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE RESTRICT,
            title TEXT NOT NULL,
            expected_entry_count INTEGER NOT NULL,
            imported_entry_count INTEGER NOT NULL,
            imported_group_count INTEGER NOT NULL,
            extraction_method TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            imported_utc TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS rare_word_groups (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES rare_word_datasets(id) ON DELETE CASCADE,
            source_index INTEGER NOT NULL,
            sheet_name TEXT NOT NULL,
            source_row INTEGER NOT NULL,
            source_cell TEXT NOT NULL,
            group_label TEXT NOT NULL,
            UNIQUE(dataset_id, source_index),
            UNIQUE(dataset_id, group_label)
        );

        CREATE TABLE IF NOT EXISTS rare_word_entries (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES rare_word_datasets(id) ON DELETE CASCADE,
            group_id INTEGER NOT NULL
                REFERENCES rare_word_groups(id) ON DELETE RESTRICT,
            source_index INTEGER NOT NULL,
            sheet_name TEXT NOT NULL,
            source_row INTEGER NOT NULL,
            pair_order INTEGER NOT NULL,
            hanzi_cell TEXT NOT NULL,
            pinyin_cell TEXT NOT NULL,
            hanzi TEXT NOT NULL,
            pinyin_raw TEXT NOT NULL,
            pinyin_nfc TEXT NOT NULL,
            raw_hanzi_cell TEXT NOT NULL,
            raw_pinyin_cell TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            UNIQUE(dataset_id, source_index),
            UNIQUE(dataset_id, sheet_name, source_row, pair_order)
        );

        CREATE INDEX IF NOT EXISTS idx_rare_word_entries_hanzi
            ON rare_word_entries(hanzi);
        CREATE INDEX IF NOT EXISTS idx_rare_word_entries_pinyin
            ON rare_word_entries(pinyin_nfc);
        CREATE INDEX IF NOT EXISTS idx_rare_word_entries_group
            ON rare_word_entries(group_id, source_index);

        CREATE VIEW IF NOT EXISTS rare_word_group_list AS
        SELECT g.source_index, g.group_label, g.sheet_name,
               g.source_row, g.source_cell
          FROM rare_word_groups AS g
          JOIN rare_word_datasets AS d ON d.id=g.dataset_id
         WHERE d.dataset_key='psc-2021-rare-difficult-words'
         ORDER BY g.source_index;

        CREATE VIEW IF NOT EXISTS rare_word_list AS
        SELECT e.source_index, e.hanzi, e.pinyin_nfc AS pinyin,
               g.group_label, e.sheet_name, e.hanzi_cell, e.pinyin_cell
          FROM rare_word_entries AS e
          JOIN rare_word_datasets AS d ON d.id=e.dataset_id
          JOIN rare_word_groups AS g ON g.id=e.group_id
         WHERE d.dataset_key='psc-2021-rare-difficult-words'
         ORDER BY e.source_index;
        """
    )


def protected_counts(conn: sqlite3.Connection) -> dict[str, int]:
    tables = (
        "entries", "issues", "manual_corrections", "manual_review_history",
        "neutral_tone_datasets", "neutral_tone_entries",
        "erhua_datasets", "erhua_categories", "erhua_entries",
    )
    result: dict[str, int] = {}
    for table in tables:
        exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
        ).fetchone()
        result[table] = (
            int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
            if exists else 0
        )
    return result


def make_backup(database: Path) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    target = database.with_name(
        f"{database.stem}.before_rare_words_import.{stamp}{database.suffix}"
    )
    source_conn = sqlite3.connect(database)
    target_conn = sqlite3.connect(target)
    try:
        source_conn.backup(target_conn)
    finally:
        target_conn.close()
        source_conn.close()
    return target


def prepare_document(
    conn: sqlite3.Connection,
    path: Path,
    unit_count: int,
    engine: str,
    version: str,
    detection: str,
    recognition: str,
) -> int:
    source_hash = sha256_file(path)
    now = utc_now()
    row = conn.execute(
        "SELECT id FROM documents WHERE source_sha256=?", (source_hash,)
    ).fetchone()
    values = (
        str(path.resolve()), path.name, path.stat().st_size, unit_count, now,
        engine, version, detection, recognition, "zh-Latn-pinyin",
    )
    if row:
        document_id = int(row["id"])
        conn.execute(
            """UPDATE documents SET source_path=?,source_filename=?,source_size=?,
               page_count=?,updated_utc=?,ocr_engine=?,ocr_version=?,
               detection_model=?,recognition_model=?,language=? WHERE id=?""",
            (*values, document_id),
        )
        return document_id
    cursor = conn.execute(
        """INSERT INTO documents(source_path,source_filename,source_sha256,
           source_size,page_count,created_utc,updated_utc,ocr_engine,ocr_version,
           detection_model,recognition_model,language)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            str(path.resolve()), path.name, source_hash, path.stat().st_size,
            unit_count, now, now, engine, version, detection, recognition,
            "zh-Latn-pinyin",
        ),
    )
    return int(cursor.lastrowid)


def import_dataset(
    database: Path,
    workbook_path: Path,
    reference_pdf: Path,
    groups: Sequence[RareWordGroup],
    entries: Sequence[RareWordEntry],
    sheet_counts: Sequence[int],
) -> dict[str, Any]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required") from exc

    conn = sqlite3.connect(database, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=30000")
    before = protected_counts(conn)
    now = utc_now()
    workbook_hash = sha256_file(workbook_path)
    reference_hash = sha256_file(reference_pdf)
    try:
        require_core_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        ensure_rare_word_schema(conn)
        workbook_document_id = prepare_document(
            conn, workbook_path, len(EXPECTED_SHEETS), "XLSX cell extraction",
            "@oai/artifact-tool", "worksheet used ranges", "stored cell values",
        )
        reference_document_id = prepare_document(
            conn, reference_pdf, len(EXPECTED_SHEET_COUNTS), "Reference PDF text layer",
            pdfplumber.__version__, "vector table lines", "embedded Unicode text",
        )

        group_sheet_counts = {
            name: sum(1 for group in groups if group.sheet_name == name)
            for name in EXPECTED_SHEETS
        }
        conn.execute("DELETE FROM pages WHERE document_id=?", (workbook_document_id,))
        conn.execute("DELETE FROM pages WHERE document_id=?", (reference_document_id,))
        for index, (sheet_name, entry_count) in enumerate(
            zip(EXPECTED_SHEETS, sheet_counts), start=1
        ):
            evidence = json_text(
                {
                    "sheet_name": sheet_name,
                    "entry_count": entry_count,
                    "group_count": group_sheet_counts[sheet_name],
                }
            )
            conn.execute(
                """INSERT INTO pages(document_id,page_number,status,span_count,
                   entry_count,ocr_json,updated_utc) VALUES(?,?,?,?,?,?,?)""",
                (
                    workbook_document_id, index, "sheet_extracted",
                    entry_count * 2 + group_sheet_counts[sheet_name], entry_count,
                    evidence, now,
                ),
            )
            conn.execute(
                """INSERT INTO pages(document_id,page_number,status,span_count,
                   entry_count,ocr_json,updated_utc) VALUES(?,?,?,?,?,?,?)""",
                (
                    reference_document_id, index, "reference_validated",
                    entry_count * 2 + group_sheet_counts[sheet_name], entry_count,
                    evidence, now,
                ),
            )

        dataset = conn.execute(
            "SELECT id FROM rare_word_datasets WHERE dataset_key=?", (DATASET_KEY,)
        ).fetchone()
        if dataset:
            dataset_id = int(dataset["id"])
            conn.execute("DELETE FROM rare_word_entries WHERE dataset_id=?", (dataset_id,))
            conn.execute("DELETE FROM rare_word_groups WHERE dataset_id=?", (dataset_id,))
            conn.execute(
                """UPDATE rare_word_datasets SET workbook_document_id=?,
                   reference_document_id=?,title=?,expected_entry_count=?,
                   imported_entry_count=?,imported_group_count=?,extraction_method=?,
                   extraction_version=1,imported_utc=? WHERE id=?""",
                (
                    workbook_document_id, reference_document_id, DATASET_TITLE,
                    EXPECTED_ENTRY_COUNT, len(entries), len(groups),
                    "artifact-tool XLSX cells validated against PDF tables", now,
                    dataset_id,
                ),
            )
        else:
            cursor = conn.execute(
                """INSERT INTO rare_word_datasets(dataset_key,workbook_document_id,
                   reference_document_id,title,expected_entry_count,
                   imported_entry_count,imported_group_count,extraction_method,
                   extraction_version,imported_utc) VALUES(?,?,?,?,?,?,?,?,1,?)""",
                (
                    DATASET_KEY, workbook_document_id, reference_document_id,
                    DATASET_TITLE, EXPECTED_ENTRY_COUNT, len(entries), len(groups),
                    "artifact-tool XLSX cells validated against PDF tables", now,
                ),
            )
            dataset_id = int(cursor.lastrowid)

        group_ids: dict[int, int] = {}
        for group in groups:
            cursor = conn.execute(
                """INSERT INTO rare_word_groups(dataset_id,source_index,sheet_name,
                   source_row,source_cell,group_label) VALUES(?,?,?,?,?,?)""",
                (
                    dataset_id, group.source_index, group.sheet_name,
                    group.source_row, group.source_cell, group.group_label,
                ),
            )
            group_ids[group.source_index] = int(cursor.lastrowid)

        conn.executemany(
            """INSERT INTO rare_word_entries(dataset_id,group_id,source_index,
               sheet_name,source_row,pair_order,hanzi_cell,pinyin_cell,hanzi,
               pinyin_raw,pinyin_nfc,raw_hanzi_cell,raw_pinyin_cell,evidence_json)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                (
                    dataset_id, group_ids[entry.group_source_index],
                    entry.source_index, entry.sheet_name, entry.source_row,
                    entry.pair_order, entry.hanzi_cell, entry.pinyin_cell,
                    entry.hanzi, entry.pinyin_raw, entry.pinyin_nfc,
                    entry.raw_hanzi_cell, entry.raw_pinyin_cell,
                    json_text(
                        {
                            "workbook_sha256": workbook_hash,
                            "reference_pdf_sha256": reference_hash,
                            "hanzi_cell": entry.hanzi_cell,
                            "pinyin_cell": entry.pinyin_cell,
                        }
                    ),
                )
                for entry in entries
            ),
        )
        conn.execute(
            "INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)",
            ("rare_word_dataset_schema_version", "1"),
        )
        after = protected_counts(conn)
        if after != before:
            raise RuntimeError(
                f"protected table counts changed: before={before}, after={after}"
            )
        stored_entries = int(
            conn.execute("SELECT COUNT(*) FROM rare_word_entries WHERE dataset_id=?", (dataset_id,)).fetchone()[0]
        )
        stored_groups = int(
            conn.execute("SELECT COUNT(*) FROM rare_word_groups WHERE dataset_id=?", (dataset_id,)).fetchone()[0]
        )
        if stored_entries != EXPECTED_ENTRY_COUNT or stored_groups != len(EXPECTED_GROUPS):
            raise RuntimeError(
                f"stored counts differ: entries={stored_entries}, groups={stored_groups}"
            )
        conn.commit()
        return {
            "dataset_id": dataset_id,
            "workbook_document_id": workbook_document_id,
            "reference_document_id": reference_document_id,
            "stored_entry_count": stored_entries,
            "stored_group_count": stored_groups,
            "protected_counts": after,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("extracted_json", type=Path)
    parser.add_argument("workbook", type=Path)
    parser.add_argument("reference_pdf", type=Path)
    parser.add_argument("database", type=Path)
    parser.add_argument("--write", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    for path in (args.extracted_json, args.workbook, args.reference_pdf, args.database):
        if not path.is_file():
            raise FileNotFoundError(path)
    groups, entries, sheet_counts, metadata = parse_workbook_json(args.extracted_json)
    summary = validate_workbook_entries(groups, entries, sheet_counts)
    summary.update(validate_against_pdf(groups, entries, args.reference_pdf))
    output: dict[str, Any] = {
        "mode": "write" if args.write else "dry-run",
        "workbook": str(args.workbook.resolve()),
        "workbook_sha256": sha256_file(args.workbook),
        "reference_pdf": str(args.reference_pdf.resolve()),
        "reference_pdf_sha256": sha256_file(args.reference_pdf),
        **summary,
    }
    if args.write:
        backup = make_backup(args.database)
        output["backup"] = str(backup)
        output.update(
            import_dataset(
                args.database, args.workbook, args.reference_pdf,
                groups, entries, sheet_counts,
            )
        )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
