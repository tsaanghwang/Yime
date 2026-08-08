#!/usr/bin/env python3
"""Import pronunciation tips from the PSC 50-passage reading material.

The plain-text export is retained as the readable text source.  Pronunciation
entries are extracted independently from the TXT and the reference PDF.  PDF
word geometry supplies the primary entry observations; TXT observations are
stored as corroborating provenance.  Source numbering defects are preserved
and surfaced through a dedicated review queue rather than silently corrected.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from import_psc_neutral_tone_pdf import (
    json_text,
    normalize_hanzi,
    require_core_schema,
    sha256_file,
    utc_now,
)


DATASET_KEY = "psc-2021-fifty-passage-pronunciation-tips"
DATASET_TITLE = "普通话水平测试50篇短文朗读语音提示"
EXPECTED_PASSAGE_COUNT = 50
WORK_RE = re.compile(r"^\s*作品\s*(\d{1,2})\s*号\s*节选自\s*(.+?)\s*$")
ITEM_MARKER_RE = re.compile(r"(?<!\d)(\d{1,2})[\.、]\s*")
PAGE_FOOTER_RE = re.compile(r"\s*-\d+-\s*$")


@dataclass(frozen=True)
class Passage:
    work_no: int
    source_heading: str
    attribution: str
    title: str
    pdf_page_number: int
    txt_start_line: int
    txt_end_line: int
    txt_has_tip_label: bool


@dataclass(frozen=True)
class Observation:
    work_no: int
    entry_order: int
    source_item_no: int
    source_item_occurrence: int
    term: str
    pinyin_raw: str
    pinyin_nfc: str
    source_kind: str
    source_locator: str
    raw_text: str
    evidence: dict[str, Any]


@dataclass(frozen=True)
class MergedEntry:
    work_no: int
    entry_order: int
    source_item_no: int
    source_item_occurrence: int
    term: str
    pinyin_raw: str
    pinyin_nfc: str
    pdf_observation: Observation
    txt_observation: Observation | None
    review_status: str


@dataclass(frozen=True)
class ImportIssue:
    work_no: int
    entry_order: int | None
    issue_type: str
    severity: str
    message: str
    details: dict[str, Any]


def latin_start_index(value: str) -> int | None:
    for index, char in enumerate(value):
        name = unicodedata.name(char, "")
        if name.startswith("LATIN"):
            return index
    return None


def normalize_term(value: str) -> str:
    return normalize_hanzi(PAGE_FOOTER_RE.sub("", value)).strip(" ;；，,")


def normalize_passage_pinyin(value: str) -> tuple[str, str]:
    raw = PAGE_FOOTER_RE.sub("", value).strip(" ;；，,")
    raw = unicodedata.normalize("NFC", raw)
    nfc = unicodedata.normalize("NFC", unicodedata.normalize("NFKC", raw))
    return raw, "".join(nfc.split()).lower()


def split_term_pinyin(payload: str) -> tuple[str, str, str]:
    cleaned = PAGE_FOOTER_RE.sub("", payload).strip()
    start = latin_start_index(cleaned)
    if start is None:
        return normalize_term(cleaned), "", ""
    term = normalize_term(cleaned[:start])
    pinyin_raw, pinyin_nfc = normalize_passage_pinyin(cleaned[start:])
    return term, pinyin_raw, pinyin_nfc


def split_marked_text(value: str) -> list[tuple[int, str]]:
    matches = list(ITEM_MARKER_RE.finditer(value))
    result: list[tuple[int, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(value)
        payload = value[match.end():end].strip()
        if payload:
            result.append((int(match.group(1)), payload))
    return result


def parse_heading(work_no: int, heading: str) -> tuple[str, str]:
    match = WORK_RE.match(heading)
    if not match or int(match.group(1)) != work_no:
        raise ValueError(f"invalid work heading: {heading!r}")
    citation = match.group(2).strip()
    title_match = re.search(r"《(.+?)》", citation)
    if title_match:
        title = title_match.group(1).strip()
        attribution = citation[: title_match.start()].strip(" ，,")
    else:
        title = citation
        attribution = ""
    return attribution, title


def find_txt_passages(lines: Sequence[str]) -> list[Passage]:
    starts: list[tuple[int, int, str]] = []
    for index, line in enumerate(lines):
        match = WORK_RE.match(line)
        if match:
            starts.append((index, int(match.group(1)), line.strip()))
    numbers = [work_no for _, work_no, _ in starts]
    if numbers != list(range(1, EXPECTED_PASSAGE_COUNT + 1)):
        raise ValueError(f"expected works 1..50, found {numbers}")

    passages: list[Passage] = []
    for position, (start, work_no, heading) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        attribution, title = parse_heading(work_no, heading)
        passages.append(
            Passage(
                work_no=work_no,
                source_heading=heading,
                attribution=attribution,
                title=title,
                pdf_page_number=work_no + 1,
                txt_start_line=start + 1,
                txt_end_line=end,
                txt_has_tip_label=any("语音提示" in line for line in lines[start:end]),
            )
        )
    return passages


def observation_from_payload(
    *,
    work_no: int,
    entry_order: int,
    source_item_no: int,
    occurrence: int,
    payload: str,
    source_kind: str,
    locator: str,
    raw_text: str,
    evidence: dict[str, Any],
) -> Observation:
    term, pinyin_raw, pinyin_nfc = split_term_pinyin(payload)
    return Observation(
        work_no=work_no,
        entry_order=entry_order,
        source_item_no=source_item_no,
        source_item_occurrence=occurrence,
        term=term,
        pinyin_raw=pinyin_raw,
        pinyin_nfc=pinyin_nfc,
        source_kind=source_kind,
        source_locator=locator,
        raw_text=raw_text,
        evidence=evidence,
    )


def extract_txt_observations(
    txt_path: Path,
) -> tuple[list[Passage], dict[int, list[Observation]], list[str]]:
    lines = txt_path.read_text(encoding="utf-8-sig").splitlines()
    passages = find_txt_passages(lines)
    observations: dict[int, list[Observation]] = {}

    for passage in passages:
        block_start = passage.txt_start_line - 1
        block_end = passage.txt_end_line
        block = lines[block_start:block_end]
        rows: list[tuple[int, str]] = []
        for offset, line in enumerate(block):
            if ITEM_MARKER_RE.match(line):
                rows.append((block_start + offset + 1, line.strip()))

        occurrence_counts: Counter[int] = Counter()
        items: list[Observation] = []
        for line_number, row in rows:
            for source_item_no, payload in split_marked_text(row):
                occurrence_counts[source_item_no] += 1
                items.append(
                    observation_from_payload(
                        work_no=passage.work_no,
                        entry_order=len(items) + 1,
                        source_item_no=source_item_no,
                        occurrence=occurrence_counts[source_item_no],
                        payload=payload,
                        source_kind="txt",
                        locator=f"line:{line_number}",
                        raw_text=f"{source_item_no}.{payload}",
                        evidence={"line_number": line_number},
                    )
                )
        observations[passage.work_no] = items
    return passages, observations, lines


def group_pdf_words(words: Sequence[dict[str, Any]], tolerance: float = 2.5) -> list[list[dict[str, Any]]]:
    rows: list[list[dict[str, Any]]] = []
    for word in sorted(words, key=lambda item: (float(item["top"]), float(item["x0"]))):
        if not rows or abs(float(word["top"]) - float(rows[-1][0]["top"])) > tolerance:
            rows.append([word])
        else:
            rows[-1].append(word)
    for row in rows:
        row.sort(key=lambda item: float(item["x0"]))
    return rows


def draft_pdf_word_items(words: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    """Recover numbered items, including pinyin wrapped below a term.

    The source uses three visual columns.  A long item may put its pinyin on the
    next line directly below the numbered term, so a simple row join attaches
    that pinyin to the neighboring column.  Unnumbered Latin words are instead
    attached to the closest preceding incomplete item in the same column.
    """

    drafts: list[dict[str, Any]] = []
    ordered_words = [word for row in group_pdf_words(words) for word in row]
    for word_index, word in enumerate(ordered_words, start=1):
        text = str(word["text"])
        x0 = float(word["x0"])
        top = float(word["top"])
        marker_matches = list(ITEM_MARKER_RE.finditer(text))
        if marker_matches:
            marked: list[tuple[int, str]] = []
            for marker_index, marker in enumerate(marker_matches):
                end = (
                    marker_matches[marker_index + 1].start()
                    if marker_index + 1 < len(marker_matches) else len(text)
                )
                marked.append((int(marker.group(1)), text[marker.end():end].strip()))
            for source_item_no, payload in marked:
                drafts.append(
                    {
                        "source_item_no": source_item_no,
                        "payload": payload,
                        "raw_text": f"{source_item_no}.{payload}",
                        "x0": x0,
                        "top": top,
                        "word_index": word_index,
                    }
                )
            continue

        if latin_start_index(text) is None:
            continue
        candidates = []
        for draft in drafts:
            _, _, pinyin_nfc = split_term_pinyin(str(draft["payload"]))
            vertical_gap = top - float(draft["top"])
            horizontal_gap = abs(x0 - float(draft["x0"]))
            if not pinyin_nfc and -2.5 <= vertical_gap <= 35 and horizontal_gap <= 100:
                candidates.append((horizontal_gap, abs(vertical_gap), draft))
        if not candidates:
            continue
        _, _, target = min(candidates, key=lambda value: (value[0], value[1]))
        target["payload"] = f"{target['payload']} {text}"
        target["raw_text"] = f"{target['raw_text']} {text}"

    drafts.sort(key=lambda item: (float(item["top"]), float(item["x0"]), int(item["word_index"])))
    return drafts


def extract_pdf_observations(
    pdf_path: Path,
    passages: Sequence[Passage],
) -> tuple[dict[int, list[Observation]], int]:
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required") from exc

    observations: dict[int, list[Observation]] = {}
    with pdfplumber.open(pdf_path) as pdf:
        page_count = len(pdf.pages)
        if page_count < EXPECTED_PASSAGE_COUNT + 1:
            raise ValueError(f"expected at least 51 PDF pages, found {page_count}")
        for passage in passages:
            page = pdf.pages[passage.pdf_page_number - 1]
            words = page.extract_words(keep_blank_chars=False, use_text_flow=False)
            label_words = [word for word in words if "语音提示" in str(word["text"])]
            threshold = (
                min(float(word["top"]) for word in label_words) - 2
                if label_words else float(page.height) * 0.58
            )
            selected = [
                word for word in words
                if float(word["top"]) >= threshold
                and float(word["top"]) < float(page.height) * 0.95
            ]
            drafts = draft_pdf_word_items(selected)
            occurrence_counts: Counter[int] = Counter()
            items: list[Observation] = []
            for draft in drafts:
                source_item_no = int(draft["source_item_no"])
                occurrence_counts[source_item_no] += 1
                items.append(
                    observation_from_payload(
                        work_no=passage.work_no,
                        entry_order=len(items) + 1,
                        source_item_no=source_item_no,
                        occurrence=occurrence_counts[source_item_no],
                        payload=str(draft["payload"]),
                        source_kind="pdf",
                        locator=(
                            f"page:{passage.pdf_page_number};"
                            f"top:{float(draft['top']):.3f};x0:{float(draft['x0']):.3f}"
                        ),
                        raw_text=str(draft["raw_text"]),
                        evidence={
                            "page_number": passage.pdf_page_number,
                            "word_index": int(draft["word_index"]),
                            "top": round(float(draft["top"]), 3),
                            "x0": round(float(draft["x0"]), 3),
                        },
                    )
                )
            observations[passage.work_no] = items
    return observations, page_count


def observation_match_key(item: Observation) -> tuple[str, str]:
    return item.term, item.pinyin_nfc


def merge_observations(
    passages: Sequence[Passage],
    pdf_items: dict[int, list[Observation]],
    txt_items: dict[int, list[Observation]],
) -> tuple[list[MergedEntry], list[ImportIssue], dict[str, Any]]:
    entries: list[MergedEntry] = []
    issues: list[ImportIssue] = []
    work_counts: list[int] = []

    for passage in passages:
        work_no = passage.work_no
        pdf_rows = list(pdf_items.get(work_no, []))
        txt_rows = list(txt_items.get(work_no, []))
        work_counts.append(len(pdf_rows))

        if not passage.txt_has_tip_label:
            issues.append(
                ImportIssue(
                    work_no, None, "missing_txt_tip_label", "warning",
                    "TXT 中缺少语音提示标题，但编号条目仍可解析",
                    {"txt_start_line": passage.txt_start_line},
                )
            )

        pdf_numbers = [item.source_item_no for item in pdf_rows]
        number_counts = Counter(pdf_numbers)
        duplicate_numbers = sorted(number for number, count in number_counts.items() if count > 1)
        maximum = max(pdf_numbers, default=0)
        missing_numbers = sorted(set(range(1, maximum + 1)) - set(pdf_numbers))
        if duplicate_numbers:
            issues.append(
                ImportIssue(
                    work_no, None, "source_duplicate_item_number", "warning",
                    "原 PDF 的语音提示存在重复编号",
                    {"duplicate_numbers": duplicate_numbers},
                )
            )
        if missing_numbers:
            issues.append(
                ImportIssue(
                    work_no, None, "source_missing_item_number", "warning",
                    "原 PDF 的语音提示存在跳号",
                    {"missing_numbers": missing_numbers, "maximum": maximum},
                )
            )

        txt_by_key: dict[tuple[str, str], list[Observation]] = defaultdict(list)
        txt_by_term: dict[str, list[Observation]] = defaultdict(list)
        for item in txt_rows:
            txt_by_key[observation_match_key(item)].append(item)
            txt_by_term[item.term].append(item)

        used_txt: set[int] = set()
        for pdf_item in pdf_rows:
            match: Observation | None = None
            for candidate in txt_by_key.get(observation_match_key(pdf_item), []):
                if id(candidate) not in used_txt:
                    match = candidate
                    break
            if match is None:
                for candidate in txt_by_term.get(pdf_item.term, []):
                    if id(candidate) not in used_txt:
                        match = candidate
                        break
            if match is not None:
                used_txt.add(id(match))

            review_status = "accepted"
            if not pdf_item.term or not pdf_item.pinyin_nfc:
                review_status = "needs_review"
                issues.append(
                    ImportIssue(
                        work_no, pdf_item.entry_order, "incomplete_pdf_pair", "error",
                        "PDF 观察记录无法拆成完整的字词与拼音",
                        {"raw_text": pdf_item.raw_text},
                    )
                )
            elif match is None:
                review_status = "needs_review"
                issues.append(
                    ImportIssue(
                        work_no, pdf_item.entry_order, "txt_observation_missing", "warning",
                        "PDF 条目在 TXT 中没有可匹配的观察记录",
                        {"term": pdf_item.term, "pinyin": pdf_item.pinyin_raw},
                    )
                )
            elif match.pinyin_nfc and match.pinyin_nfc != pdf_item.pinyin_nfc:
                review_status = "needs_review"
                issues.append(
                    ImportIssue(
                        work_no, pdf_item.entry_order, "source_pinyin_disagreement", "warning",
                        "PDF 与 TXT 的拼音观察不一致",
                        {
                            "term": pdf_item.term,
                            "pdf_pinyin": pdf_item.pinyin_raw,
                            "txt_pinyin": match.pinyin_raw,
                        },
                    )
                )

            entries.append(
                MergedEntry(
                    work_no=work_no,
                    entry_order=pdf_item.entry_order,
                    source_item_no=pdf_item.source_item_no,
                    source_item_occurrence=pdf_item.source_item_occurrence,
                    term=pdf_item.term,
                    pinyin_raw=pdf_item.pinyin_raw,
                    pinyin_nfc=pdf_item.pinyin_nfc,
                    pdf_observation=pdf_item,
                    txt_observation=match,
                    review_status=review_status,
                )
            )

        unmatched_txt = [item for item in txt_rows if id(item) not in used_txt]
        for item in unmatched_txt:
            issues.append(
                ImportIssue(
                    work_no, None, "unmatched_txt_observation", "warning",
                    "TXT 条目在 PDF 主观察中没有可匹配记录",
                    {"raw_text": item.raw_text, "locator": item.source_locator},
                )
            )

    summary = {
        "passage_count": len(passages),
        "entry_count": len(entries),
        "work_entry_counts": work_counts,
        "accepted_entry_count": sum(entry.review_status == "accepted" for entry in entries),
        "review_entry_count": sum(entry.review_status != "accepted" for entry in entries),
        "issue_count": len(issues),
        "issue_type_counts": dict(sorted(Counter(issue.issue_type for issue in issues).items())),
    }
    return entries, issues, summary


def pinyin_characters_are_valid(value: str) -> bool:
    for char in value:
        if char.isspace() or char in "()'’·:-/":
            continue
        category = unicodedata.category(char)
        if category.startswith("L") or category.startswith("M"):
            continue
        return False
    return True


def validate_entries(
    passages: Sequence[Passage],
    entries: Sequence[MergedEntry],
    summary: dict[str, Any],
) -> dict[str, Any]:
    errors: list[str] = []
    if len(passages) != EXPECTED_PASSAGE_COUNT:
        errors.append(f"expected 50 passages, found {len(passages)}")
    if [passage.work_no for passage in passages] != list(range(1, 51)):
        errors.append("passage numbers are not exactly 1..50")
    if not entries:
        errors.append("no pronunciation entries extracted")
    for entry in entries:
        if entry.term and not any(
            char == "〇" or 0x3400 <= ord(char) <= 0x9FFF
            for char in entry.term
        ):
            errors.append(f"work {entry.work_no} item {entry.entry_order}: term lacks CJK")
        if entry.pinyin_raw and not pinyin_characters_are_valid(entry.pinyin_raw):
            errors.append(
                f"work {entry.work_no} item {entry.entry_order}: invalid pinyin {entry.pinyin_raw!r}"
            )
    if errors:
        raise ValueError("passage pronunciation quality gate failed:\n- " + "\n- ".join(errors[:30]))
    return summary


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP VIEW IF EXISTS passage_pronunciation_review_queue;
        DROP VIEW IF EXISTS passage_pronunciation_list;

        CREATE TABLE IF NOT EXISTS passage_pronunciation_datasets (
            id INTEGER PRIMARY KEY,
            dataset_key TEXT NOT NULL UNIQUE,
            txt_document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE RESTRICT,
            pdf_document_id INTEGER NOT NULL UNIQUE
                REFERENCES documents(id) ON DELETE RESTRICT,
            title TEXT NOT NULL,
            imported_passage_count INTEGER NOT NULL,
            imported_entry_count INTEGER NOT NULL,
            extraction_method TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            imported_utc TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS passage_pronunciation_passages (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES passage_pronunciation_datasets(id) ON DELETE CASCADE,
            work_no INTEGER NOT NULL,
            source_heading TEXT NOT NULL,
            attribution TEXT NOT NULL,
            title TEXT NOT NULL,
            pdf_page_number INTEGER NOT NULL,
            txt_start_line INTEGER NOT NULL,
            txt_end_line INTEGER NOT NULL,
            txt_has_tip_label INTEGER NOT NULL CHECK(txt_has_tip_label IN (0,1)),
            UNIQUE(dataset_id, work_no)
        );

        CREATE TABLE IF NOT EXISTS passage_pronunciation_entries (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES passage_pronunciation_datasets(id) ON DELETE CASCADE,
            passage_id INTEGER NOT NULL
                REFERENCES passage_pronunciation_passages(id) ON DELETE CASCADE,
            source_index INTEGER NOT NULL,
            entry_order INTEGER NOT NULL,
            source_item_no INTEGER NOT NULL,
            source_item_occurrence INTEGER NOT NULL,
            term TEXT NOT NULL,
            pinyin_raw TEXT NOT NULL,
            pinyin_nfc TEXT NOT NULL,
            review_status TEXT NOT NULL
                CHECK(review_status IN ('accepted','needs_review')),
            pdf_locator TEXT NOT NULL,
            txt_locator TEXT,
            pdf_raw_text TEXT NOT NULL,
            txt_raw_text TEXT,
            evidence_json TEXT NOT NULL,
            UNIQUE(dataset_id, source_index),
            UNIQUE(passage_id, entry_order)
        );

        CREATE TABLE IF NOT EXISTS passage_pronunciation_issues (
            id INTEGER PRIMARY KEY,
            dataset_id INTEGER NOT NULL
                REFERENCES passage_pronunciation_datasets(id) ON DELETE CASCADE,
            passage_id INTEGER NOT NULL
                REFERENCES passage_pronunciation_passages(id) ON DELETE CASCADE,
            entry_id INTEGER
                REFERENCES passage_pronunciation_entries(id) ON DELETE CASCADE,
            issue_type TEXT NOT NULL,
            severity TEXT NOT NULL CHECK(severity IN ('warning','error')),
            message TEXT NOT NULL,
            details_json TEXT NOT NULL,
            review_status TEXT NOT NULL DEFAULT 'pending'
                CHECK(review_status IN ('pending','resolved','ignored'))
        );

        CREATE INDEX IF NOT EXISTS idx_passage_pronunciation_term
            ON passage_pronunciation_entries(term);
        CREATE INDEX IF NOT EXISTS idx_passage_pronunciation_pinyin
            ON passage_pronunciation_entries(pinyin_nfc);
        CREATE INDEX IF NOT EXISTS idx_passage_pronunciation_work
            ON passage_pronunciation_entries(passage_id, entry_order);
        CREATE INDEX IF NOT EXISTS idx_passage_pronunciation_issue_status
            ON passage_pronunciation_issues(review_status, severity, issue_type);

        CREATE VIEW IF NOT EXISTS passage_pronunciation_list AS
        SELECT p.work_no, p.title, e.entry_order, e.source_item_no,
               e.source_item_occurrence, e.term, e.pinyin_nfc AS pinyin,
               e.review_status, p.pdf_page_number, e.pdf_locator, e.txt_locator
         FROM passage_pronunciation_entries AS e
          JOIN passage_pronunciation_passages AS p ON p.id=e.passage_id
          JOIN passage_pronunciation_datasets AS d ON d.id=e.dataset_id
         WHERE d.dataset_key='psc-2021-fifty-passage-pronunciation-tips'
         ORDER BY p.work_no, e.source_item_no,
                  e.source_item_occurrence, e.entry_order;

        CREATE VIEW IF NOT EXISTS passage_pronunciation_review_queue AS
        SELECT i.id AS issue_id, p.work_no, p.title, e.entry_order,
               e.term, e.pinyin_nfc AS pinyin, i.issue_type, i.severity,
               i.message, i.details_json, i.review_status
          FROM passage_pronunciation_issues AS i
          JOIN passage_pronunciation_passages AS p ON p.id=i.passage_id
          LEFT JOIN passage_pronunciation_entries AS e ON e.id=i.entry_id
          JOIN passage_pronunciation_datasets AS d ON d.id=i.dataset_id
         WHERE d.dataset_key='psc-2021-fifty-passage-pronunciation-tips'
           AND i.review_status='pending'
         ORDER BY p.work_no, COALESCE(e.entry_order,0), i.id;
        """
    )


def protected_counts(conn: sqlite3.Connection) -> dict[str, int]:
    tables = (
        "entries", "issues", "manual_corrections", "manual_review_history",
        "neutral_tone_datasets", "neutral_tone_entries",
        "erhua_datasets", "erhua_categories", "erhua_entries",
        "rare_word_datasets", "rare_word_groups", "rare_word_entries",
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
        f"{database.stem}.before_passage_pronunciation_import.{stamp}{database.suffix}"
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
    txt_path: Path,
    pdf_path: Path,
    passages: Sequence[Passage],
    entries: Sequence[MergedEntry],
    issues: Sequence[ImportIssue],
    pdf_page_count: int,
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
    txt_hash = sha256_file(txt_path)
    pdf_hash = sha256_file(pdf_path)
    try:
        require_core_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        ensure_schema(conn)
        txt_document_id = prepare_document(
            conn, txt_path, EXPECTED_PASSAGE_COUNT, "Word plain-text export", "1",
            "work headings and numbered pronunciation lines", "stored Unicode text",
        )
        pdf_document_id = prepare_document(
            conn, pdf_path, pdf_page_count, "Reference PDF word geometry",
            pdfplumber.__version__, "pdfplumber extract_words", "embedded Unicode text",
        )

        conn.execute("DELETE FROM pages WHERE document_id=?", (txt_document_id,))
        conn.execute("DELETE FROM pages WHERE document_id=?", (pdf_document_id,))
        entry_counts = Counter(entry.work_no for entry in entries)
        issue_counts = Counter(issue.work_no for issue in issues)
        for passage in passages:
            evidence = json_text(
                {
                    "work_no": passage.work_no,
                    "title": passage.title,
                    "entry_count": entry_counts[passage.work_no],
                    "issue_count": issue_counts[passage.work_no],
                    "txt_lines": [passage.txt_start_line, passage.txt_end_line],
                    "pdf_page_number": passage.pdf_page_number,
                }
            )
            conn.execute(
                """INSERT INTO pages(document_id,page_number,status,span_count,
                   entry_count,ocr_json,updated_utc) VALUES(?,?,?,?,?,?,?)""",
                (
                    txt_document_id, passage.work_no, "passage_indexed",
                    passage.txt_end_line - passage.txt_start_line + 1,
                    entry_counts[passage.work_no], evidence, now,
                ),
            )
            conn.execute(
                """INSERT INTO pages(document_id,page_number,status,span_count,
                   entry_count,ocr_json,updated_utc) VALUES(?,?,?,?,?,?,?)""",
                (
                    pdf_document_id, passage.pdf_page_number,
                    "pronunciation_geometry_extracted", entry_counts[passage.work_no],
                    entry_counts[passage.work_no], evidence, now,
                ),
            )

        existing = conn.execute(
            "SELECT id FROM passage_pronunciation_datasets WHERE dataset_key=?",
            (DATASET_KEY,),
        ).fetchone()
        if existing:
            dataset_id = int(existing["id"])
            conn.execute(
                "DELETE FROM passage_pronunciation_issues WHERE dataset_id=?",
                (dataset_id,),
            )
            conn.execute(
                "DELETE FROM passage_pronunciation_entries WHERE dataset_id=?",
                (dataset_id,),
            )
            conn.execute(
                "DELETE FROM passage_pronunciation_passages WHERE dataset_id=?",
                (dataset_id,),
            )
            conn.execute(
                """UPDATE passage_pronunciation_datasets SET txt_document_id=?,
                   pdf_document_id=?,title=?,imported_passage_count=?,
                   imported_entry_count=?,extraction_method=?,extraction_version=1,
                   imported_utc=? WHERE id=?""",
                (
                    txt_document_id, pdf_document_id, DATASET_TITLE, len(passages),
                    len(entries), "PDF word geometry cross-checked with TXT export",
                    now, dataset_id,
                ),
            )
        else:
            cursor = conn.execute(
                """INSERT INTO passage_pronunciation_datasets(dataset_key,
                   txt_document_id,pdf_document_id,title,imported_passage_count,
                   imported_entry_count,extraction_method,extraction_version,
                   imported_utc) VALUES(?,?,?,?,?,?,?,1,?)""",
                (
                    DATASET_KEY, txt_document_id, pdf_document_id, DATASET_TITLE,
                    len(passages), len(entries),
                    "PDF word geometry cross-checked with TXT export", now,
                ),
            )
            dataset_id = int(cursor.lastrowid)

        passage_ids: dict[int, int] = {}
        for passage in passages:
            cursor = conn.execute(
                """INSERT INTO passage_pronunciation_passages(dataset_id,work_no,
                   source_heading,attribution,title,pdf_page_number,txt_start_line,
                   txt_end_line,txt_has_tip_label) VALUES(?,?,?,?,?,?,?,?,?)""",
                (
                    dataset_id, passage.work_no, passage.source_heading,
                    passage.attribution, passage.title, passage.pdf_page_number,
                    passage.txt_start_line, passage.txt_end_line,
                    int(passage.txt_has_tip_label),
                ),
            )
            passage_ids[passage.work_no] = int(cursor.lastrowid)

        entry_ids: dict[tuple[int, int], int] = {}
        for source_index, entry in enumerate(entries, start=1):
            txt_observation = entry.txt_observation
            cursor = conn.execute(
                """INSERT INTO passage_pronunciation_entries(dataset_id,passage_id,
                   source_index,entry_order,source_item_no,source_item_occurrence,
                   term,pinyin_raw,pinyin_nfc,review_status,pdf_locator,txt_locator,
                   pdf_raw_text,txt_raw_text,evidence_json)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    dataset_id, passage_ids[entry.work_no], source_index,
                    entry.entry_order, entry.source_item_no,
                    entry.source_item_occurrence, entry.term, entry.pinyin_raw,
                    entry.pinyin_nfc, entry.review_status,
                    entry.pdf_observation.source_locator,
                    txt_observation.source_locator if txt_observation else None,
                    entry.pdf_observation.raw_text,
                    txt_observation.raw_text if txt_observation else None,
                    json_text(
                        {
                            "txt_sha256": txt_hash,
                            "pdf_sha256": pdf_hash,
                            "pdf": entry.pdf_observation.evidence,
                            "txt": txt_observation.evidence if txt_observation else None,
                        }
                    ),
                ),
            )
            entry_ids[(entry.work_no, entry.entry_order)] = int(cursor.lastrowid)

        for issue in issues:
            conn.execute(
                """INSERT INTO passage_pronunciation_issues(dataset_id,passage_id,
                   entry_id,issue_type,severity,message,details_json,review_status)
                   VALUES(?,?,?,?,?,?,?,'pending')""",
                (
                    dataset_id, passage_ids[issue.work_no],
                    entry_ids.get((issue.work_no, issue.entry_order))
                    if issue.entry_order is not None else None,
                    issue.issue_type, issue.severity, issue.message,
                    json_text(issue.details),
                ),
            )

        conn.execute(
            "INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)",
            ("passage_pronunciation_dataset_schema_version", "1"),
        )
        after = protected_counts(conn)
        if after != before:
            raise RuntimeError(
                f"protected table counts changed: before={before}, after={after}"
            )
        stored_passages = int(conn.execute(
            "SELECT COUNT(*) FROM passage_pronunciation_passages WHERE dataset_id=?",
            (dataset_id,),
        ).fetchone()[0])
        stored_entries = int(conn.execute(
            "SELECT COUNT(*) FROM passage_pronunciation_entries WHERE dataset_id=?",
            (dataset_id,),
        ).fetchone()[0])
        stored_issues = int(conn.execute(
            "SELECT COUNT(*) FROM passage_pronunciation_issues WHERE dataset_id=?",
            (dataset_id,),
        ).fetchone()[0])
        if stored_passages != len(passages) or stored_entries != len(entries):
            raise RuntimeError(
                f"stored counts differ: passages={stored_passages}, entries={stored_entries}"
            )
        conn.commit()
        return {
            "dataset_id": dataset_id,
            "txt_document_id": txt_document_id,
            "pdf_document_id": pdf_document_id,
            "stored_passage_count": stored_passages,
            "stored_entry_count": stored_entries,
            "stored_issue_count": stored_issues,
            "protected_counts": after,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("txt", type=Path)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("database", type=Path)
    parser.add_argument("--write", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    for path in (args.txt, args.pdf, args.database):
        if not path.is_file():
            raise FileNotFoundError(path)

    passages, txt_items, _ = extract_txt_observations(args.txt)
    pdf_items, pdf_page_count = extract_pdf_observations(args.pdf, passages)
    entries, issues, summary = merge_observations(passages, pdf_items, txt_items)
    validate_entries(passages, entries, summary)
    output: dict[str, Any] = {
        "mode": "write" if args.write else "dry-run",
        "txt": str(args.txt.resolve()),
        "txt_sha256": sha256_file(args.txt),
        "pdf": str(args.pdf.resolve()),
        "pdf_sha256": sha256_file(args.pdf),
        "pdf_page_count": pdf_page_count,
        **summary,
    }
    if args.write:
        backup = make_backup(args.database)
        output["backup"] = str(backup)
        output.update(
            import_dataset(
                args.database, args.txt, args.pdf, passages, entries, issues,
                pdf_page_count,
            )
        )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
