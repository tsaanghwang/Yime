#!/usr/bin/env python3
"""Import the PSC erhua word-list PDF as an independent audited dataset."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from import_psc_neutral_tone_pdf import (
    bbox_json,
    has_cjk,
    has_latin,
    json_text,
    normalize_hanzi,
    normalize_pinyin,
    pinyin_characters_are_valid,
    require_core_schema,
    sha256_file,
    strip_watermark_lines,
    utc_now,
)


DATASET_KEY = "psc-2021-erhua-words"
DATASET_TITLE = "普通话水平测试用儿化词语表"
EXPECTED_PAGE_COUNTS = (84, 74, 42)
EXPECTED_CATEGORY_COUNT = 37


@dataclass(frozen=True)
class ErhuaCategory:
    source_index: int
    page_number: int
    table_order: int
    row_order: int
    rule_raw: str
    rule_nfc: str
    base_final: str
    erhua_final: str
    nasalized: bool
    evidence_json: str


@dataclass(frozen=True)
class ErhuaEntry:
    source_index: int
    category_source_index: int
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


def normalize_rule(value: str | None) -> tuple[str, str]:
    raw = strip_watermark_lines(value)
    normalized = unicodedata.normalize("NFC", unicodedata.normalize("NFKC", raw))
    return raw, "".join(normalized.split())


def parse_rule(rule_nfc: str) -> tuple[str, str, bool]:
    nasalized = "(鼻化)" in rule_nfc
    body = rule_nfc.replace("(鼻化)", "")
    if ">" in body:
        base_final, erhua_final = body.split(">", 1)
    elif ":" in body:
        # One heading in the source uses a colon where the rendered glyph is
        # visually a relation separator.  Colons after '>' belong to forms
        # such as i:er and are therefore not handled here.
        base_final, erhua_final = body.split(":", 1)
    else:
        raise ValueError(f"not an erhua category rule: {rule_nfc!r}")
    if not base_final or not erhua_final:
        raise ValueError(f"incomplete erhua category rule: {rule_nfc!r}")
    return base_final, erhua_final, nasalized


def is_rule_row(values: Sequence[str | None]) -> bool:
    nonempty = [index for index, value in enumerate(values) if (value or "").strip()]
    if nonempty != [0]:
        return False
    _, normalized = normalize_rule(values[0])
    return ">" in normalized or ":" in normalized


def extract_erhua(
    source_pdf: Path,
) -> tuple[list[ErhuaCategory], list[ErhuaEntry], list[int]]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required for direct PDF extraction") from exc

    categories: list[ErhuaCategory] = []
    entries: list[ErhuaEntry] = []
    page_counts: list[int] = []
    current_category: ErhuaCategory | None = None

    with pdfplumber.open(source_pdf) as pdf:
        if len(pdf.pages) != len(EXPECTED_PAGE_COUNTS):
            raise ValueError(
                f"expected {len(EXPECTED_PAGE_COUNTS)} pages, found {len(pdf.pages)}"
            )

        for page_number, page in enumerate(pdf.pages, start=1):
            page_start = len(entries)
            tables = page.find_tables()
            if len(tables) != 1:
                raise ValueError(
                    f"page {page_number}: expected one vector table, found {len(tables)}"
                )

            for table_order, table in enumerate(tables, start=1):
                extracted_rows = table.extract()
                if len(extracted_rows) != len(table.rows):
                    raise ValueError(
                        f"page {page_number}: table text and geometry row counts differ"
                    )

                for row_order, (values, row_geometry) in enumerate(
                    zip(extracted_rows, table.rows), start=1
                ):
                    values = list(values or [])
                    cells = list(row_geometry.cells)
                    if len(values) != len(cells) or len(values) % 2:
                        raise ValueError(
                            f"page {page_number} row {row_order}: invalid cell pairing"
                        )

                    if is_rule_row(values):
                        rule_raw, rule_nfc = normalize_rule(values[0])
                        base_final, erhua_final, nasalized = parse_rule(rule_nfc)
                        current_category = ErhuaCategory(
                            source_index=len(categories) + 1,
                            page_number=page_number,
                            table_order=table_order,
                            row_order=row_order,
                            rule_raw=rule_raw,
                            rule_nfc=rule_nfc,
                            base_final=base_final,
                            erhua_final=erhua_final,
                            nasalized=nasalized,
                            evidence_json=json_text(
                                {
                                    "page_bbox": bbox_json(page.bbox),
                                    "table_bbox": bbox_json(table.bbox),
                                    "rule_bbox": bbox_json(cells[0]),
                                }
                            ),
                        )
                        categories.append(current_category)
                        continue

                    for cell_index in range(0, len(values), 2):
                        raw_hanzi = values[cell_index] or ""
                        raw_pinyin = values[cell_index + 1] or ""
                        hanzi = normalize_hanzi(raw_hanzi)
                        pinyin_raw, pinyin_nfc = normalize_pinyin(raw_pinyin)
                        if not hanzi and not pinyin_nfc:
                            continue
                        if not hanzi or not pinyin_nfc:
                            raise ValueError(
                                f"page {page_number} row {row_order} pair "
                                f"{cell_index // 2 + 1}: incomplete entry "
                                f"{raw_hanzi!r} / {raw_pinyin!r}"
                            )
                        if current_category is None:
                            raise ValueError(
                                f"page {page_number} row {row_order}: entry precedes category"
                            )

                        entries.append(
                            ErhuaEntry(
                                source_index=len(entries) + 1,
                                category_source_index=current_category.source_index,
                                page_number=page_number,
                                table_order=table_order,
                                row_order=row_order,
                                pair_order=cell_index // 2 + 1,
                                hanzi=hanzi,
                                pinyin_raw=pinyin_raw,
                                pinyin_nfc=pinyin_nfc,
                                raw_hanzi_cell=raw_hanzi,
                                raw_pinyin_cell=raw_pinyin,
                                evidence_json=json_text(
                                    {
                                        "page_bbox": bbox_json(page.bbox),
                                        "table_bbox": bbox_json(table.bbox),
                                        "hanzi_bbox": bbox_json(cells[cell_index]),
                                        "pinyin_bbox": bbox_json(cells[cell_index + 1]),
                                    }
                                ),
                            )
                        )

            page_counts.append(len(entries) - page_start)

    return categories, entries, page_counts


def validate_erhua(
    categories: Sequence[ErhuaCategory],
    entries: Sequence[ErhuaEntry],
    page_counts: Sequence[int],
    expected_count: int,
) -> dict[str, Any]:
    errors: list[str] = []
    if len(entries) != expected_count:
        errors.append(f"expected {expected_count} entries, found {len(entries)}")
    if len(categories) != EXPECTED_CATEGORY_COUNT:
        errors.append(
            f"expected {EXPECTED_CATEGORY_COUNT} categories, found {len(categories)}"
        )
    if tuple(page_counts) != EXPECTED_PAGE_COUNTS:
        errors.append(
            f"page counts differ: expected {EXPECTED_PAGE_COUNTS}, "
            f"found {tuple(page_counts)}"
        )

    category_indexes = {category.source_index for category in categories}
    category_entry_counts = {index: 0 for index in category_indexes}
    for expected_index, entry in enumerate(entries, start=1):
        if entry.source_index != expected_index:
            errors.append(
                f"entry index discontinuity at {expected_index}: {entry.source_index}"
            )
        if entry.category_source_index not in category_indexes:
            errors.append(
                f"entry {entry.source_index}: unknown category "
                f"{entry.category_source_index}"
            )
        else:
            category_entry_counts[entry.category_source_index] += 1
        if not has_cjk(entry.hanzi) or "儿" not in entry.hanzi:
            errors.append(
                f"entry {entry.source_index}: invalid erhua word {entry.hanzi!r}"
            )
        if not has_latin(entry.pinyin_nfc) or "r" not in entry.pinyin_nfc.lower():
            errors.append(
                f"entry {entry.source_index}: invalid erhua pinyin {entry.pinyin_nfc!r}"
            )
        if not pinyin_characters_are_valid(entry.pinyin_nfc):
            errors.append(
                f"entry {entry.source_index}: unexpected pinyin character in "
                f"{entry.pinyin_nfc!r}"
            )
        if "\ufffd" in entry.hanzi + entry.pinyin_nfc:
            errors.append(f"entry {entry.source_index}: replacement character present")

    empty_categories = [
        index for index, count in category_entry_counts.items() if count == 0
    ]
    if empty_categories:
        errors.append(f"categories contain no entries: {empty_categories}")

    exact_pairs: dict[tuple[str, str], list[int]] = {}
    for entry in entries:
        exact_pairs.setdefault((entry.hanzi, entry.pinyin_nfc), []).append(
            entry.source_index
        )
    duplicate_pairs = {
        pair: indexes for pair, indexes in exact_pairs.items() if len(indexes) > 1
    }
    if duplicate_pairs:
        errors.append(f"exact duplicate pairs found: {duplicate_pairs}")

    rule_names = [category.rule_nfc for category in categories]
    if len(rule_names) != len(set(rule_names)):
        errors.append("duplicate category rules found")

    if errors:
        raise ValueError("erhua quality gate failed:\n- " + "\n- ".join(errors))

    return {
        "entry_count": len(entries),
        "category_count": len(categories),
        "page_counts": list(page_counts),
        "exact_duplicate_pairs": 0,
        "nasalized_category_count": sum(
            1 for category in categories if category.nasalized
        ),
    }


def ensure_erhua_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS erhua_datasets (
            id INTEGER PRIMARY KEY,
            dataset_key TEXT NOT NULL UNIQUE,
            document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            expected_entry_count INTEGER NOT NULL,
            imported_entry_count INTEGER NOT NULL,
            imported_category_count INTEGER NOT NULL,
            extraction_method TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            imported_utc TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS erhua_categories (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES erhua_datasets(id) ON DELETE CASCADE,
            source_index INTEGER NOT NULL,
            page_number INTEGER NOT NULL,
            table_order INTEGER NOT NULL,
            row_order INTEGER NOT NULL,
            rule_raw TEXT NOT NULL,
            rule_nfc TEXT NOT NULL,
            base_final TEXT NOT NULL,
            erhua_final TEXT NOT NULL,
            nasalized INTEGER NOT NULL CHECK(nasalized IN (0,1)),
            evidence_json TEXT NOT NULL,
            UNIQUE(dataset_id, source_index),
            UNIQUE(dataset_id, rule_nfc)
        );

        CREATE TABLE IF NOT EXISTS erhua_entries (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES erhua_datasets(id) ON DELETE CASCADE,
            category_id INTEGER NOT NULL
                REFERENCES erhua_categories(id) ON DELETE RESTRICT,
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

        CREATE INDEX IF NOT EXISTS idx_erhua_entries_hanzi
            ON erhua_entries(hanzi);
        CREATE INDEX IF NOT EXISTS idx_erhua_entries_pinyin
            ON erhua_entries(pinyin_nfc);
        CREATE INDEX IF NOT EXISTS idx_erhua_entries_category
            ON erhua_entries(category_id, source_index);

        CREATE VIEW IF NOT EXISTS erhua_category_list AS
        SELECT c.source_index, c.rule_nfc AS rule, c.base_final,
               c.erhua_final, c.nasalized, c.page_number
          FROM erhua_categories AS c
          JOIN erhua_datasets AS d ON d.id=c.dataset_id
         WHERE d.dataset_key='psc-2021-erhua-words'
         ORDER BY c.source_index;

        CREATE VIEW IF NOT EXISTS erhua_word_list AS
        SELECT e.source_index, e.hanzi, e.pinyin_nfc AS pinyin,
               c.source_index AS category_index, c.rule_nfc AS category_rule,
               e.page_number, e.row_order, e.pair_order
          FROM erhua_entries AS e
          JOIN erhua_datasets AS d ON d.id=e.dataset_id
          JOIN erhua_categories AS c ON c.id=e.category_id
         WHERE d.dataset_key='psc-2021-erhua-words'
         ORDER BY e.source_index;
        """
    )


def protected_counts(conn: sqlite3.Connection) -> dict[str, int]:
    tables = (
        "entries",
        "issues",
        "manual_corrections",
        "manual_review_history",
        "neutral_tone_datasets",
        "neutral_tone_entries",
    )
    result: dict[str, int] = {}
    for table in tables:
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
        f"{database.stem}.before_erhua_import.{stamp}{database.suffix}"
    )
    source_conn = sqlite3.connect(database)
    target_conn = sqlite3.connect(target)
    try:
        source_conn.backup(target_conn)
    finally:
        target_conn.close()
        source_conn.close()
    return target


def import_erhua(
    database: Path,
    source_pdf: Path,
    categories: Sequence[ErhuaCategory],
    entries: Sequence[ErhuaEntry],
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
    before = protected_counts(conn)
    now = utc_now()
    source_hash = sha256_file(source_pdf)
    try:
        require_core_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        ensure_erhua_schema(conn)

        document = conn.execute(
            "SELECT id FROM documents WHERE source_sha256=?", (source_hash,)
        ).fetchone()
        document_values = (
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
        )
        if document:
            document_id = int(document["id"])
            conn.execute(
                """
                UPDATE documents SET
                    source_path=?, source_filename=?, source_size=?, page_count=?,
                    updated_utc=?, ocr_engine=?, ocr_version=?, detection_model=?,
                    recognition_model=?, language=? WHERE id=?
                """,
                (*document_values, document_id),
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
        page_category_counts = {
            page: sum(1 for category in categories if category.page_number == page)
            for page in range(1, len(page_counts) + 1)
        }
        for page_number, entry_count in enumerate(page_counts, start=1):
            category_count = page_category_counts[page_number]
            conn.execute(
                """
                INSERT INTO pages(
                    document_id, page_number, status, span_count, entry_count,
                    ocr_json, updated_utc
                ) VALUES(?,?,?,?,?,?,?)
                """,
                (
                    document_id,
                    page_number,
                    "text_extracted",
                    entry_count * 2 + category_count,
                    entry_count,
                    json_text(
                        {
                            "method": "pdfplumber vector-table extraction",
                            "entry_count": entry_count,
                            "category_count": category_count,
                        }
                    ),
                    now,
                ),
            )

        dataset = conn.execute(
            "SELECT id FROM erhua_datasets WHERE dataset_key=?", (DATASET_KEY,)
        ).fetchone()
        if dataset:
            dataset_id = int(dataset["id"])
            conn.execute(
                "DELETE FROM erhua_entries WHERE dataset_id=?", (dataset_id,)
            )
            conn.execute(
                "DELETE FROM erhua_categories WHERE dataset_id=?", (dataset_id,)
            )
            conn.execute(
                """
                UPDATE erhua_datasets SET
                    document_id=?, title=?, expected_entry_count=?,
                    imported_entry_count=?, imported_category_count=?,
                    extraction_method=?, extraction_version=1, imported_utc=?
                WHERE id=?
                """,
                (
                    document_id,
                    DATASET_TITLE,
                    expected_count,
                    len(entries),
                    len(categories),
                    "pdfplumber text layer and vector tables",
                    now,
                    dataset_id,
                ),
            )
        else:
            cursor = conn.execute(
                """
                INSERT INTO erhua_datasets(
                    dataset_key, document_id, title, expected_entry_count,
                    imported_entry_count, imported_category_count,
                    extraction_method, extraction_version, imported_utc
                ) VALUES(?,?,?,?,?,?,?,1,?)
                """,
                (
                    DATASET_KEY,
                    document_id,
                    DATASET_TITLE,
                    expected_count,
                    len(entries),
                    len(categories),
                    "pdfplumber text layer and vector tables",
                    now,
                ),
            )
            dataset_id = int(cursor.lastrowid)

        category_ids: dict[int, int] = {}
        for category in categories:
            cursor = conn.execute(
                """
                INSERT INTO erhua_categories(
                    dataset_id, source_index, page_number, table_order, row_order,
                    rule_raw, rule_nfc, base_final, erhua_final, nasalized,
                    evidence_json
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    dataset_id,
                    category.source_index,
                    category.page_number,
                    category.table_order,
                    category.row_order,
                    category.rule_raw,
                    category.rule_nfc,
                    category.base_final,
                    category.erhua_final,
                    int(category.nasalized),
                    category.evidence_json,
                ),
            )
            category_ids[category.source_index] = int(cursor.lastrowid)

        conn.executemany(
            """
            INSERT INTO erhua_entries(
                dataset_id, category_id, source_index, page_number, table_order,
                row_order, pair_order, hanzi, pinyin_raw, pinyin_nfc,
                raw_hanzi_cell, raw_pinyin_cell, evidence_json
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                (
                    dataset_id,
                    category_ids[entry.category_source_index],
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
            ("erhua_dataset_schema_version", "1"),
        )

        after = protected_counts(conn)
        if after != before:
            raise RuntimeError(
                f"protected table counts changed: before={before}, after={after}"
            )
        stored_entries = int(
            conn.execute(
                "SELECT COUNT(*) FROM erhua_entries WHERE dataset_id=?",
                (dataset_id,),
            ).fetchone()[0]
        )
        stored_categories = int(
            conn.execute(
                "SELECT COUNT(*) FROM erhua_categories WHERE dataset_id=?",
                (dataset_id,),
            ).fetchone()[0]
        )
        if stored_entries != expected_count or stored_categories != len(categories):
            raise RuntimeError(
                f"stored counts differ: entries={stored_entries}, "
                f"categories={stored_categories}"
            )
        conn.commit()
        return {
            "document_id": document_id,
            "dataset_id": dataset_id,
            "stored_entry_count": stored_entries,
            "stored_category_count": stored_categories,
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
    parser.add_argument("--expected-count", type=int, default=200)
    parser.add_argument(
        "--write",
        action="store_true",
        help="back up and update the database; otherwise run read-only",
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

    categories, entries, page_counts = extract_erhua(source_pdf)
    summary = validate_erhua(categories, entries, page_counts, args.expected_count)
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
            import_erhua(
                database,
                source_pdf,
                categories,
                entries,
                page_counts,
                args.expected_count,
            )
        )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
