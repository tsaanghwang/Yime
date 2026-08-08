#!/usr/bin/env python3
"""OCR an image-only PSC outline PDF into an auditable SQLite database.

The database deliberately keeps two layers:

* lossless OCR evidence (page JSON, spans, confidence and geometry), and
* best-effort structured entries (table number, source index, Han text, pinyin).

The conversion is resumable.  A completed page is not OCRed again unless
``--force`` is supplied.  Parsing can therefore be improved later without
having to repeat the expensive OCR pass.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import re
import sqlite3
import statistics
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any, Iterable, Sequence


SCHEMA_VERSION = 1
ANCHOR_RE = re.compile(r"^\s*(\d{1,5})(?:\s+|(?=[\u3400-\u9fff])|$)(.*)$")


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


def connect_database(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY,
            source_path TEXT NOT NULL,
            source_filename TEXT NOT NULL,
            source_sha256 TEXT NOT NULL UNIQUE,
            source_size INTEGER NOT NULL,
            page_count INTEGER NOT NULL,
            created_utc TEXT NOT NULL,
            updated_utc TEXT NOT NULL,
            ocr_engine TEXT NOT NULL,
            ocr_version TEXT NOT NULL,
            detection_model TEXT NOT NULL,
            recognition_model TEXT NOT NULL,
            language TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS pages (
            document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL,
            table_number INTEGER,
            image_path TEXT,
            image_width INTEGER,
            image_height INTEGER,
            image_sha256 TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            elapsed_ms INTEGER,
            span_count INTEGER,
            entry_count INTEGER,
            ocr_json TEXT,
            error_message TEXT,
            updated_utc TEXT NOT NULL,
            PRIMARY KEY (document_id, page_number)
        );

        CREATE TABLE IF NOT EXISTS ocr_spans (
            id INTEGER PRIMARY KEY,
            document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL,
            span_order INTEGER NOT NULL,
            column_number INTEGER NOT NULL,
            text TEXT NOT NULL,
            confidence REAL,
            x1 REAL NOT NULL,
            y1 REAL NOT NULL,
            x2 REAL NOT NULL,
            y2 REAL NOT NULL,
            polygon_json TEXT,
            word_boxes_json TEXT,
            word_text_json TEXT,
            UNIQUE (document_id, page_number, span_order)
        );

        CREATE TABLE IF NOT EXISTS entries (
            id INTEGER PRIMARY KEY,
            document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            table_number INTEGER,
            source_index INTEGER NOT NULL,
            page_number INTEGER NOT NULL,
            column_number INTEGER NOT NULL,
            row_order INTEGER NOT NULL,
            index_origin TEXT NOT NULL,
            hanzi TEXT,
            pinyin_raw TEXT,
            pinyin_nfc TEXT,
            raw_text TEXT NOT NULL,
            minimum_confidence REAL,
            mean_confidence REAL,
            status TEXT NOT NULL,
            evidence_span_ids_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS issues (
            id INTEGER PRIMARY KEY,
            document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER,
            table_number INTEGER,
            source_index INTEGER,
            severity TEXT NOT NULL,
            code TEXT NOT NULL,
            message TEXT NOT NULL,
            evidence_json TEXT,
            created_utc TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_spans_page
            ON ocr_spans(document_id, page_number, column_number, y1, x1);
        CREATE INDEX IF NOT EXISTS idx_entries_source
            ON entries(document_id, table_number, source_index);
        CREATE INDEX IF NOT EXISTS idx_entries_page
            ON entries(document_id, page_number, column_number, row_order);
        CREATE INDEX IF NOT EXISTS idx_issues_code
            ON issues(document_id, code, severity);

        CREATE VIEW IF NOT EXISTS accepted_entries AS
        SELECT table_number, source_index, hanzi, pinyin_raw, pinyin_nfc,
               page_number, column_number, minimum_confidence, mean_confidence
          FROM entries
         WHERE status = 'accepted';

        CREATE VIEW IF NOT EXISTS review_queue AS
        SELECT e.table_number, e.source_index, e.hanzi, e.pinyin_raw,
               e.raw_text, e.page_number, e.column_number, e.index_origin,
               e.minimum_confidence, i.severity, i.code, i.message,
               i.evidence_json
          FROM entries AS e
          LEFT JOIN issues AS i
            ON i.document_id = e.document_id
           AND i.page_number = e.page_number
           AND i.source_index = e.source_index
         WHERE e.status = 'needs_review';

        CREATE VIEW IF NOT EXISTS page_quality_summary AS
        SELECT p.page_number, p.table_number, p.status, p.span_count,
               p.entry_count, p.elapsed_ms,
               SUM(CASE WHEN e.status = 'needs_review' THEN 1 ELSE 0 END)
                   AS entries_needing_review
          FROM pages AS p
          LEFT JOIN entries AS e
            ON e.document_id = p.document_id AND e.page_number = p.page_number
         GROUP BY p.document_id, p.page_number;
        """
    )
    conn.execute(
        "INSERT OR REPLACE INTO metadata(key, value) VALUES('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    conn.commit()
    return conn


def prepare_document(
    conn: sqlite3.Connection,
    source_pdf: Path,
    page_count: int,
    ocr_version: str,
    detection_model: str,
    recognition_model: str,
    language: str,
) -> int:
    source_hash = sha256_file(source_pdf)
    now = utc_now()
    row = conn.execute(
        "SELECT id FROM documents WHERE source_sha256 = ?", (source_hash,)
    ).fetchone()
    if row:
        document_id = int(row["id"])
        conn.execute(
            """
            UPDATE documents
               SET source_path=?, source_filename=?, source_size=?, page_count=?,
                   updated_utc=?, ocr_version=?, detection_model=?,
                   recognition_model=?, language=?
             WHERE id=?
            """,
            (
                str(source_pdf.resolve()),
                source_pdf.name,
                source_pdf.stat().st_size,
                page_count,
                now,
                ocr_version,
                detection_model,
                recognition_model,
                language,
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
                page_count,
                now,
                now,
                "PaddleOCR",
                ocr_version,
                detection_model,
                recognition_model,
                language,
            ),
        )
        document_id = int(cursor.lastrowid)

    conn.executemany(
        """
        INSERT OR IGNORE INTO pages(document_id, page_number, status, updated_utc)
        VALUES(?, ?, 'pending', ?)
        """,
        ((document_id, page, now) for page in range(1, page_count + 1)),
    )
    conn.commit()
    return document_id


def extract_page_image(reader: Any, page_number: int, image_dir: Path) -> Path:
    image_dir.mkdir(parents=True, exist_ok=True)
    target = image_dir / f"page-{page_number:04d}.png"
    if target.exists() and target.stat().st_size > 0:
        return target

    images = list(reader.pages[page_number - 1].images)
    if not images:
        raise RuntimeError(f"page {page_number} contains no extractable image")
    chosen = max(images, key=lambda item: item.image.width * item.image.height)
    image = chosen.image.convert("RGB")
    image.save(target, format="PNG", optimize=False)
    return target


def page_column_boundaries(
    texts: Sequence[str], boxes: Sequence[Sequence[float]], page_width: int
) -> tuple[float, float]:
    """Estimate the left edges of columns 2 and 3 from numeric index spans."""
    numeric_left_edges: list[float] = []
    for text, box in zip(texts, boxes):
        match = ANCHOR_RE.match(str(text))
        if match and 0 < int(match.group(1)) <= 50000:
            numeric_left_edges.append(float(box[0]))
    second_band = [x for x in numeric_left_edges if page_width * 0.20 <= x < page_width * 0.55]
    third_band = [x for x in numeric_left_edges if x >= page_width * 0.55]
    second_start = statistics.median(second_band) if second_band else page_width * 0.30
    third_start = statistics.median(third_band) if third_band else page_width * 0.65
    return second_start - 8.0, third_start - 8.0


def box_column(box: Sequence[float], boundaries: tuple[float, float]) -> int:
    left = float(box[0])
    if left < boundaries[0]:
        return 1
    if left < boundaries[1]:
        return 2
    return 3


def is_han(character: str) -> bool:
    value = ord(character)
    return (
        0x3400 <= value <= 0x4DBF
        or 0x4E00 <= value <= 0x9FFF
        or 0xF900 <= value <= 0xFAFF
        or 0x20000 <= value <= 0x323AF
    )


def split_hanzi_pinyin(raw_text: str) -> tuple[str | None, str | None]:
    hanzi = "".join(character for character in raw_text if is_han(character))
    remainder = "".join(
        " " if is_han(character) else character for character in raw_text
    )
    remainder = re.sub(r"\s+", " ", remainder).strip(" ,，;；")
    return (hanzi or None, remainder or None)


def median_step(anchors: list[dict[str, Any]]) -> float:
    candidates: list[float] = []
    ordered = sorted(anchors, key=lambda item: item["index"])
    for left, right in zip(ordered, ordered[1:]):
        index_delta = right["index"] - left["index"]
        y_delta = right["yc"] - left["yc"]
        if 1 <= index_delta <= 5 and y_delta > 0:
            candidates.append(y_delta / index_delta)
    return statistics.median(candidates) if candidates else 40.0


def interpolate_y(index: int, anchors: list[dict[str, Any]], step: float) -> float:
    exact = next((item for item in anchors if item["index"] == index), None)
    if exact:
        return float(exact["yc"])
    below = [item for item in anchors if item["index"] < index]
    above = [item for item in anchors if item["index"] > index]
    if below and above:
        left = max(below, key=lambda item: item["index"])
        right = min(above, key=lambda item: item["index"])
        fraction = (index - left["index"]) / (right["index"] - left["index"])
        return float(left["yc"] + fraction * (right["yc"] - left["yc"]))
    if below:
        left = max(below, key=lambda item: item["index"])
        return float(left["yc"] + (index - left["index"]) * step)
    right = min(above, key=lambda item: item["index"])
    return float(right["yc"] - (right["index"] - index) * step)


def parse_page_spans(
    spans: list[dict[str, Any]], page_width: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    entries: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []

    for column in (1, 2, 3):
        column_spans = [item for item in spans if item["column"] == column]
        column_left = (column - 1) * page_width / 3.0
        anchor_zone_right = column_left + page_width / 3.0 * 0.13
        anchors: list[dict[str, Any]] = []
        content: list[dict[str, Any]] = []
        candidates: list[dict[str, Any]] = []
        for span in column_spans:
            match = ANCHOR_RE.match(span["text"])
            if match:
                source_index = int(match.group(1))
                if 0 < source_index <= 50000:
                    anchor = dict(span)
                    anchor["index"] = source_index
                    anchor["remainder"] = match.group(2).strip()
                    candidates.append(anchor)
                    continue
            content.append(span)

        # OCR sometimes merges an index with the Han/pinyin span, making its box
        # start farther right than the normal index gutter.  Conversely, it can
        # duplicate the last digit of the real index at the start of the content
        # span (for example ``1 依靠`` beside the true ``7181``).  Select the
        # locally coherent index cluster rather than trusting either shape alone.
        gutter_candidates = [
            item for item in candidates if item["x1"] <= anchor_zone_right
        ]
        if gutter_candidates:
            center_index = statistics.median(item["index"] for item in gutter_candidates)
            anchors = [
                item for item in candidates if abs(item["index"] - center_index) <= 250
            ]
        elif candidates:
            ordered_indices = sorted(item["index"] for item in candidates)
            best_low = ordered_indices[0]
            best_count = 0
            right = 0
            for left, low in enumerate(ordered_indices):
                right = max(right, left)
                while right < len(ordered_indices) and ordered_indices[right] - low <= 250:
                    right += 1
                if right - left > best_count:
                    best_low = low
                    best_count = right - left
            anchors = [
                item for item in candidates if best_low <= item["index"] <= best_low + 250
            ]

        accepted_candidate_ids = {item["id"] for item in anchors}
        content.extend(item for item in candidates if item["id"] not in accepted_candidate_ids)

        if not anchors:
            if column_spans:
                issues.append(
                    {
                        "severity": "error",
                        "code": "column_without_index_anchors",
                        "message": f"column {column} contains OCR text but no numeric anchors",
                        "evidence": {"span_ids": [item["id"] for item in column_spans]},
                    }
                )
            continue

        # Duplicate numeric anchors are preserved as issues; the highest-confidence
        # anchor supplies the row position.
        grouped: dict[int, list[dict[str, Any]]] = {}
        for anchor in anchors:
            grouped.setdefault(anchor["index"], []).append(anchor)
        clean_anchors: list[dict[str, Any]] = []
        for source_index, group in grouped.items():
            chosen = max(group, key=lambda item: item["confidence"])
            clean_anchors.append(chosen)
            if len(group) > 1:
                issues.append(
                    {
                        "severity": "warning",
                        "code": "duplicate_page_anchor",
                        "source_index": source_index,
                        "message": f"column {column} has {len(group)} anchors for index {source_index}",
                        "evidence": {"span_ids": [item["id"] for item in group]},
                    }
                )

        clean_anchors.sort(key=lambda item: item["index"])
        step = median_step(clean_anchors)
        minimum = min(item["index"] for item in clean_anchors)
        maximum = max(item["index"] for item in clean_anchors)
        if maximum - minimum > 250:
            issues.append(
                {
                    "severity": "error",
                    "code": "implausible_column_index_range",
                    "message": f"column {column} index range {minimum}..{maximum} is implausible",
                    "evidence": {"anchors": [item["index"] for item in clean_anchors]},
                }
            )
            continue

        slots = {
            source_index: interpolate_y(source_index, clean_anchors, step)
            for source_index in range(minimum, maximum + 1)
        }
        by_index: dict[int, list[dict[str, Any]]] = {
            source_index: [] for source_index in slots
        }
        max_distance = max(24.0, step * 0.72)
        for span in content:
            nearest = min(slots, key=lambda source_index: abs(span["yc"] - slots[source_index]))
            if abs(span["yc"] - slots[nearest]) <= max_distance:
                by_index[nearest].append(span)

        anchors_by_index = {item["index"]: item for item in clean_anchors}
        for row_order, source_index in enumerate(sorted(slots), start=1):
            anchor = anchors_by_index.get(source_index)
            row_spans = sorted(by_index[source_index], key=lambda item: (item["y1"], item["x1"]))
            fragments: list[str] = []
            evidence_ids: list[int] = []
            confidence_values: list[float] = []
            if anchor:
                evidence_ids.append(anchor["id"])
                confidence_values.append(anchor["confidence"])
                if anchor["remainder"]:
                    fragments.append(anchor["remainder"])
            for span in row_spans:
                fragments.append(span["text"].strip())
                evidence_ids.append(span["id"])
                confidence_values.append(span["confidence"])
            raw_text = re.sub(r"\s+", " ", " ".join(part for part in fragments if part)).strip()
            hanzi, pinyin = split_hanzi_pinyin(raw_text)
            index_origin = "ocr" if anchor else "geometry_inferred"
            row_status = "accepted"
            if not anchor or not hanzi or not pinyin or not confidence_values:
                row_status = "needs_review"
            elif min(confidence_values) < 0.80:
                row_status = "needs_review"

            entry = {
                "source_index": source_index,
                "column": column,
                "row_order": row_order,
                "index_origin": index_origin,
                "hanzi": hanzi,
                "pinyin_raw": pinyin,
                "pinyin_nfc": unicodedata.normalize("NFC", pinyin) if pinyin else None,
                "raw_text": raw_text,
                "minimum_confidence": min(confidence_values) if confidence_values else None,
                "mean_confidence": statistics.fmean(confidence_values) if confidence_values else None,
                "status": row_status,
                "evidence_span_ids": evidence_ids,
            }
            entries.append(entry)

            if not anchor:
                issues.append(
                    {
                        "severity": "warning",
                        "code": "inferred_source_index",
                        "source_index": source_index,
                        "message": f"source index {source_index} was inferred from row geometry",
                        "evidence": {"span_ids": evidence_ids, "estimated_y": slots[source_index]},
                    }
                )
            if not hanzi:
                issues.append(
                    {
                        "severity": "error",
                        "code": "missing_hanzi",
                        "source_index": source_index,
                        "message": f"source index {source_index} has no parsed Han text",
                        "evidence": {"raw_text": raw_text, "span_ids": evidence_ids},
                    }
                )
            if not pinyin:
                issues.append(
                    {
                        "severity": "error",
                        "code": "missing_pinyin",
                        "source_index": source_index,
                        "message": f"source index {source_index} has no parsed pinyin",
                        "evidence": {"raw_text": raw_text, "span_ids": evidence_ids},
                    }
                )
            if confidence_values and min(confidence_values) < 0.80:
                issues.append(
                    {
                        "severity": "warning",
                        "code": "low_confidence_entry",
                        "source_index": source_index,
                        "message": f"source index {source_index} contains OCR confidence below 0.80",
                        "evidence": {"minimum_confidence": min(confidence_values), "span_ids": evidence_ids},
                    }
                )

    return entries, issues


def normalise_ocr_payload(payload: dict[str, Any]) -> dict[str, Any]:
    return payload.get("res", payload)


def store_page_result(
    conn: sqlite3.Connection,
    document_id: int,
    page_number: int,
    image_path: Path,
    payload: dict[str, Any],
    elapsed_ms: int,
) -> None:
    from PIL import Image

    data = normalise_ocr_payload(payload)
    texts = list(data.get("rec_texts", []))
    scores = list(data.get("rec_scores", []))
    boxes = list(data.get("rec_boxes", []))
    polygons = list(data.get("rec_polys", []))
    word_boxes = list(data.get("text_word_boxes", []))
    word_text = list(data.get("text_word", []))
    if not (len(texts) == len(scores) == len(boxes)):
        raise RuntimeError(
            f"page {page_number}: inconsistent OCR arrays "
            f"texts={len(texts)} scores={len(scores)} boxes={len(boxes)}"
        )

    with Image.open(image_path) as image:
        page_width, page_height = image.size
    column_boundaries = page_column_boundaries(texts, boxes, page_width)

    now = utc_now()
    with conn:
        conn.execute(
            "DELETE FROM issues WHERE document_id=? AND page_number=?",
            (document_id, page_number),
        )
        conn.execute(
            "DELETE FROM entries WHERE document_id=? AND page_number=?",
            (document_id, page_number),
        )
        conn.execute(
            "DELETE FROM ocr_spans WHERE document_id=? AND page_number=?",
            (document_id, page_number),
        )

        spans: list[dict[str, Any]] = []
        for order, (text, confidence, box) in enumerate(zip(texts, scores, boxes)):
            x1, y1, x2, y2 = (float(value) for value in box)
            polygon = polygons[order] if order < len(polygons) else None
            this_word_boxes = word_boxes[order] if order < len(word_boxes) else None
            this_word_text = word_text[order] if order < len(word_text) else None
            column = box_column(box, column_boundaries)
            cursor = conn.execute(
                """
                INSERT INTO ocr_spans(
                    document_id, page_number, span_order, column_number,
                    text, confidence, x1, y1, x2, y2, polygon_json,
                    word_boxes_json, word_text_json
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    document_id,
                    page_number,
                    order,
                    column,
                    str(text),
                    float(confidence),
                    x1,
                    y1,
                    x2,
                    y2,
                    json_text(polygon) if polygon is not None else None,
                    json_text(this_word_boxes) if this_word_boxes is not None else None,
                    json_text(this_word_text) if this_word_text is not None else None,
                ),
            )
            spans.append(
                {
                    "id": int(cursor.lastrowid),
                    "order": order,
                    "column": column,
                    "text": str(text),
                    "confidence": float(confidence),
                    "x1": x1,
                    "y1": y1,
                    "x2": x2,
                    "y2": y2,
                    "yc": (y1 + y2) / 2.0,
                }
            )

        entries, issues = parse_page_spans(spans, page_width)
        for entry in entries:
            conn.execute(
                """
                INSERT INTO entries(
                    document_id, table_number, source_index, page_number,
                    column_number, row_order, index_origin, hanzi, pinyin_raw,
                    pinyin_nfc, raw_text, minimum_confidence, mean_confidence,
                    status, evidence_span_ids_json
                ) VALUES(?,NULL,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    document_id,
                    entry["source_index"],
                    page_number,
                    entry["column"],
                    entry["row_order"],
                    entry["index_origin"],
                    entry["hanzi"],
                    entry["pinyin_raw"],
                    entry["pinyin_nfc"],
                    entry["raw_text"],
                    entry["minimum_confidence"],
                    entry["mean_confidence"],
                    entry["status"],
                    json_text(entry["evidence_span_ids"]),
                ),
            )
        for issue in issues:
            conn.execute(
                """
                INSERT INTO issues(
                    document_id, page_number, table_number, source_index,
                    severity, code, message, evidence_json, created_utc
                ) VALUES(?,?,NULL,?,?,?,?,?,?)
                """,
                (
                    document_id,
                    page_number,
                    issue.get("source_index"),
                    issue["severity"],
                    issue["code"],
                    issue["message"],
                    json_text(issue.get("evidence")) if issue.get("evidence") is not None else None,
                    now,
                ),
            )

        conn.execute(
            """
            UPDATE pages
               SET image_path=?, image_width=?, image_height=?, image_sha256=?,
                   status='complete', elapsed_ms=?, span_count=?, entry_count=?,
                   ocr_json=?, error_message=NULL, updated_utc=?
             WHERE document_id=? AND page_number=?
            """,
            (
                str(image_path.resolve()),
                page_width,
                page_height,
                sha256_file(image_path),
                elapsed_ms,
                len(spans),
                len(entries),
                json_text(data),
                now,
                document_id,
                page_number,
            ),
        )


def assign_table_numbers(conn: sqlite3.Connection, document_id: int) -> int:
    page_rows = conn.execute(
        """
        SELECT page_number, MIN(source_index) AS minimum_index,
               MAX(source_index) AS maximum_index
          FROM entries
         WHERE document_id=?
         GROUP BY page_number
         ORDER BY page_number
        """,
        (document_id,),
    ).fetchall()
    table_number = 1
    previous_maximum: int | None = None
    assigned = 0
    with conn:
        for row in page_rows:
            minimum = int(row["minimum_index"])
            maximum = int(row["maximum_index"])
            if previous_maximum is not None and previous_maximum > 1000 and minimum < previous_maximum * 0.25:
                table_number += 1
            page_number = int(row["page_number"])
            conn.execute(
                "UPDATE pages SET table_number=? WHERE document_id=? AND page_number=?",
                (table_number, document_id, page_number),
            )
            conn.execute(
                "UPDATE entries SET table_number=? WHERE document_id=? AND page_number=?",
                (table_number, document_id, page_number),
            )
            conn.execute(
                "UPDATE issues SET table_number=? WHERE document_id=? AND page_number=?",
                (table_number, document_id, page_number),
            )
            previous_maximum = maximum
            assigned = table_number
    return assigned


def rebuild_completeness_issues(
    conn: sqlite3.Connection,
    document_id: int,
    expected_counts: Sequence[int],
) -> None:
    now = utc_now()
    with conn:
        conn.execute(
            "DELETE FROM issues WHERE document_id=? AND page_number IS NULL",
            (document_id,),
        )
        table_count_row = conn.execute(
            "SELECT MAX(table_number) AS value FROM entries WHERE document_id=?",
            (document_id,),
        ).fetchone()
        table_count = int(table_count_row["value"] or 0)
        for table_number in range(1, table_count + 1):
            counts = conn.execute(
                """
                SELECT source_index, COUNT(*) AS occurrences
                  FROM entries
                 WHERE document_id=? AND table_number=?
                 GROUP BY source_index
                """,
                (document_id, table_number),
            ).fetchall()
            occurrence_map = {int(row["source_index"]): int(row["occurrences"]) for row in counts}
            expected = (
                int(expected_counts[table_number - 1])
                if table_number <= len(expected_counts)
                else max(occurrence_map, default=0)
            )
            for source_index in range(1, expected + 1):
                occurrences = occurrence_map.get(source_index, 0)
                if occurrences == 0:
                    conn.execute(
                        """
                        INSERT INTO issues(
                            document_id, page_number, table_number, source_index,
                            severity, code, message, evidence_json, created_utc
                        ) VALUES(?,NULL,?,?, 'error','missing_source_index',?,?,?)
                        """,
                        (
                            document_id,
                            table_number,
                            source_index,
                            f"table {table_number} is missing source index {source_index}",
                            json_text({"expected_table_count": expected}),
                            now,
                        ),
                    )
                elif occurrences > 1:
                    conn.execute(
                        """
                        INSERT INTO issues(
                            document_id, page_number, table_number, source_index,
                            severity, code, message, evidence_json, created_utc
                        ) VALUES(?,NULL,?,?, 'error','duplicate_source_index',?,?,?)
                        """,
                        (
                            document_id,
                            table_number,
                            source_index,
                            f"table {table_number} has {occurrences} entries for source index {source_index}",
                            json_text({"occurrences": occurrences}),
                            now,
                        ),
                    )


def parse_expected_counts(value: str) -> list[int]:
    if not value.strip():
        return []
    return [int(item.strip()) for item in value.split(",") if item.strip()]


def iter_import_json(directory: Path) -> Iterable[tuple[int, Path]]:
    for path in sorted(directory.rglob("page-*_res.json")):
        match = re.search(r"page-(\d+)_res\.json$", path.name)
        if match:
            yield int(match.group(1)), path


def load_ocr_pipeline(args: argparse.Namespace) -> Any:
    os.environ["PADDLE_PDX_CACHE_HOME"] = str(args.cache_dir.resolve())
    os.environ.setdefault("PADDLE_PDX_MODEL_SOURCE", "BOS")
    from paddleocr import PaddleOCR

    return PaddleOCR(
        ocr_version=args.ocr_version,
        lang=args.language,
        text_detection_model_name=args.detection_model,
        text_recognition_model_name=args.recognition_model,
        text_recognition_batch_size=args.recognition_batch_size,
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        return_word_box=True,
        device=args.device,
    )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_pdf", type=Path)
    parser.add_argument("output_sqlite", type=Path)
    parser.add_argument("--work-dir", type=Path, default=Path("tmp/psc-outline-ocr"))
    parser.add_argument("--cache-dir", type=Path, default=Path("tmp/psc-ocr-cache/paddlex"))
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--ocr-version", default="PP-OCRv6")
    parser.add_argument("--detection-model", default="PP-OCRv6_medium_det")
    parser.add_argument("--recognition-model", default="PP-OCRv6_medium_rec")
    parser.add_argument("--language", default="ch")
    parser.add_argument("--recognition-batch-size", type=int, default=8)
    parser.add_argument("--start-page", type=int, default=1)
    parser.add_argument("--end-page", type=int)
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--reparse-only",
        action="store_true",
        help="rebuild structured entries from stored page OCR JSON without running OCR",
    )
    parser.add_argument("--extract-only", action="store_true")
    parser.add_argument("--import-json-dir", type=Path)
    parser.add_argument(
        "--expected-table-counts",
        default="8361,10081",
        help="comma-separated expected row counts; empty disables fixed expectations",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)
    source_pdf = args.source_pdf.resolve()
    output_sqlite = args.output_sqlite.resolve()
    if not source_pdf.is_file():
        raise FileNotFoundError(source_pdf)
    args.work_dir.mkdir(parents=True, exist_ok=True)
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    image_dir = args.work_dir / "pages"

    from pypdf import PdfReader

    reader = PdfReader(str(source_pdf))
    page_count = len(reader.pages)
    end_page = min(args.end_page or page_count, page_count)
    if args.start_page < 1 or args.start_page > end_page:
        raise ValueError(f"invalid page range {args.start_page}..{end_page}")

    conn = connect_database(output_sqlite)
    document_id = prepare_document(
        conn,
        source_pdf,
        page_count,
        args.ocr_version,
        args.detection_model,
        args.recognition_model,
        args.language,
    )

    imported: dict[int, Path] = {}
    if args.import_json_dir:
        imported = dict(iter_import_json(args.import_json_dir.resolve()))

    pipeline = None
    processed = 0
    for page_number in range(args.start_page, end_page + 1):
        current = conn.execute(
            "SELECT status, image_path, elapsed_ms, ocr_json FROM pages "
            "WHERE document_id=? AND page_number=?",
            (document_id, page_number),
        ).fetchone()
        if args.reparse_only:
            if not current or current["status"] != "complete" or not current["ocr_json"]:
                print(f"[{page_number:04d}/{page_count:04d}] no stored OCR JSON", flush=True)
                continue
            image_path = Path(current["image_path"])
            payload = json.loads(current["ocr_json"])
            store_page_result(
                conn,
                document_id,
                page_number,
                image_path,
                payload,
                int(current["elapsed_ms"] or 0),
            )
            processed += 1
            row = conn.execute(
                "SELECT span_count, entry_count FROM pages WHERE document_id=? AND page_number=?",
                (document_id, page_number),
            ).fetchone()
            print(
                f"[{page_number:04d}/{page_count:04d}] reparsed: "
                f"{row['span_count']} spans, {row['entry_count']} entries",
                flush=True,
            )
            continue
        if current and current["status"] == "complete" and not args.force:
            print(f"[{page_number:04d}/{page_count:04d}] already complete", flush=True)
            continue

        try:
            image_path = extract_page_image(reader, page_number, image_dir)
            if args.extract_only:
                from PIL import Image

                with Image.open(image_path) as image:
                    width, height = image.size
                with conn:
                    conn.execute(
                        """
                        UPDATE pages SET image_path=?, image_width=?, image_height=?,
                               image_sha256=?, status='extracted', updated_utc=?
                         WHERE document_id=? AND page_number=?
                        """,
                        (
                            str(image_path.resolve()),
                            width,
                            height,
                            sha256_file(image_path),
                            utc_now(),
                            document_id,
                            page_number,
                        ),
                    )
                print(f"[{page_number:04d}/{page_count:04d}] extracted", flush=True)
                continue

            started = time.perf_counter()
            if page_number in imported:
                payload = json.loads(imported[page_number].read_text(encoding="utf-8"))
                source_label = f"imported {imported[page_number]}"
            else:
                if pipeline is None:
                    pipeline = load_ocr_pipeline(args)
                results = list(pipeline.predict(str(image_path), return_word_box=True))
                if len(results) != 1:
                    raise RuntimeError(f"page {page_number}: expected one OCR result, got {len(results)}")
                payload = results[0].json
                source_label = "OCR"
            elapsed_ms = round((time.perf_counter() - started) * 1000)
            store_page_result(conn, document_id, page_number, image_path, payload, elapsed_ms)
            processed += 1
            row = conn.execute(
                "SELECT span_count, entry_count FROM pages WHERE document_id=? AND page_number=?",
                (document_id, page_number),
            ).fetchone()
            print(
                f"[{page_number:04d}/{page_count:04d}] {source_label}: "
                f"{row['span_count']} spans, {row['entry_count']} entries, {elapsed_ms / 1000:.1f}s",
                flush=True,
            )
        except Exception as error:
            with conn:
                conn.execute(
                    """
                    UPDATE pages SET status='failed', error_message=?, updated_utc=?
                     WHERE document_id=? AND page_number=?
                    """,
                    (repr(error), utc_now(), document_id, page_number),
                )
            print(f"[{page_number:04d}/{page_count:04d}] FAILED: {error!r}", file=sys.stderr, flush=True)

    table_count = assign_table_numbers(conn, document_id)
    completed = int(
        conn.execute(
            "SELECT COUNT(*) FROM pages WHERE document_id=? AND status='complete'",
            (document_id,),
        ).fetchone()[0]
    )
    if completed == page_count:
        rebuild_completeness_issues(
            conn,
            document_id,
            parse_expected_counts(args.expected_table_counts),
        )
    conn.execute("UPDATE documents SET updated_utc=? WHERE id=?", (utc_now(), document_id))
    conn.commit()

    stats = conn.execute(
        """
        SELECT
          (SELECT COUNT(*) FROM pages WHERE document_id=? AND status='complete') AS pages,
          (SELECT COUNT(*) FROM ocr_spans WHERE document_id=?) AS spans,
          (SELECT COUNT(*) FROM entries WHERE document_id=?) AS entries,
          (SELECT COUNT(*) FROM entries WHERE document_id=? AND status='needs_review') AS review,
          (SELECT COUNT(*) FROM issues WHERE document_id=?) AS issues
        """,
        (document_id,) * 5,
    ).fetchone()
    integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
    print(
        f"database={output_sqlite}\n"
        f"processed_this_run={processed} complete_pages={stats['pages']}/{page_count} "
        f"tables={table_count} spans={stats['spans']} entries={stats['entries']} "
        f"needs_review={stats['review']} issues={stats['issues']} integrity={integrity}",
        flush=True,
    )
    conn.close()
    return 0 if integrity == "ok" else 2


if __name__ == "__main__":
    raise SystemExit(main())
