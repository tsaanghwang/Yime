"""Read-only audit of the canonical lexicon against PSC 2021/2024 evidence."""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import sqlite3
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Mapping, Sequence


SCHEMA_VERSION = "yime-psc-pronunciation-audit-v2"
VALID_REVIEW_DECISIONS = frozenset(
    {"accept_psc", "keep_source", "keep_both", "psc_evidence_error", "defer"}
)
SOURCE_POLICY: dict[str, dict[str, object]] = {
    "psc_main": {
        "label": "PSC 2021/2024 单音节多音节表",
        "evidence_role": "normative_pronunciation",
        "priority": 100,
    },
    "psc_neutral_tone": {
        "label": "PSC 2021 必读轻声词语表",
        "evidence_role": "lexical_neutral_tone",
        "priority": 90,
    },
    "psc_erhua": {
        "label": "PSC 2021 儿化词语表",
        "evidence_role": "erhua_policy_evidence",
        "priority": 80,
    },
    "psc_rare_word": {
        "label": "PSC 2021 生僻字难点字词",
        "evidence_role": "supplemental_pronunciation",
        "priority": 50,
    },
    "psc_passage": {
        "label": "PSC 2021 朗读篇目语音提示",
        "evidence_role": "contextual_pronunciation",
        "priority": 40,
    },
}

_ALT_SEPARATOR_RE = re.compile(r"[/／]+")
_IGNORED_PINYIN_RE = re.compile(r"[\s'’·•\-‐‑‒–—―]+")


@dataclass(frozen=True)
class Observation:
    source_kind: str
    source_key: str
    source_order: int
    text: str
    pinyin_raw: str
    locator: dict[str, object]


@dataclass(frozen=True)
class Reading:
    marked: str
    numeric: str
    normalized: str
    is_primary: bool
    reading_rank: int
    sources: str
    neutral_tone_status: str


@dataclass(frozen=True)
class AuditResult:
    outcome: str
    review_lane: str
    review_priority: int
    psc_variants: tuple[str, ...]
    canonical_readings: tuple[Reading, ...]
    accepted_readings: tuple[Reading, ...]
    matched_canonical: tuple[str, ...]
    matched_accepted: tuple[str, ...]
    unmatched: tuple[str, ...]
    explanation: str


@dataclass(frozen=True)
class AuditArtifacts:
    database: Path
    summary_json: Path
    report_markdown: Path
    review_tsv: Path
    observation_count: int
    review_observation_count: int
    review_case_count: int
    pending_case_count: int
    decided_case_count: int


@dataclass(frozen=True)
class ReviewCase:
    case_key: str
    review_lane: str
    review_priority: int
    text: str
    pinyin_forms: tuple[str, ...]
    pinyin_variants: tuple[str, ...]
    outcomes: tuple[str, ...]
    evidence_sources: tuple[str, ...]
    evidence_count: int
    canonical_readings: tuple[dict[str, object], ...]
    accepted_readings: tuple[dict[str, object], ...]
    unmatched_variants: tuple[str, ...]
    evidence_items: tuple[dict[str, object], ...]
    explanation: str
    decision: str
    selected_pinyin: str
    note: str
    reviewer: str
    updated_at_utc: str


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _review_case_key(lane: str, text: str, variants: Sequence[str]) -> str:
    payload = json.dumps(
        [lane, text, list(variants)], ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


class ReviewDecisionStore:
    """Mutable facade limited to decisions in the generated audit database."""

    def __init__(self, database: Path) -> None:
        self.database = database.resolve()
        self.connection = sqlite3.connect(self.database)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.connection.execute("PRAGMA busy_timeout = 5000")
        _require_objects(
            self.connection,
            ("review_cases", "review_decisions", "review_decision_history"),
            "audit",
        )

    def close(self) -> None:
        self.connection.close()

    def load_cases(self) -> list[ReviewCase]:
        rows = self.connection.execute(
            """
            SELECT * FROM review_case_detail
            ORDER BY review_priority DESC, review_lane, text, case_key
            """
        ).fetchall()
        result: list[ReviewCase] = []
        for row in rows:
            result.append(
                ReviewCase(
                    case_key=str(row["case_key"]),
                    review_lane=str(row["review_lane"]),
                    review_priority=int(row["review_priority"]),
                    text=str(row["text"]),
                    pinyin_forms=tuple(json.loads(row["pinyin_forms_json"])),
                    pinyin_variants=tuple(json.loads(row["pinyin_variants_json"])),
                    outcomes=tuple(json.loads(row["outcomes_json"])),
                    evidence_sources=tuple(json.loads(row["evidence_sources_json"])),
                    evidence_count=int(row["evidence_count"]),
                    canonical_readings=tuple(json.loads(row["canonical_readings_json"])),
                    accepted_readings=tuple(json.loads(row["accepted_readings_json"])),
                    unmatched_variants=tuple(json.loads(row["unmatched_variants_json"])),
                    evidence_items=tuple(json.loads(row["evidence_items_json"])),
                    explanation=str(row["explanation"]),
                    decision=str(row["decision"] or "pending"),
                    selected_pinyin=str(row["selected_pinyin"] or ""),
                    note=str(row["note"] or ""),
                    reviewer=str(row["reviewer"] or ""),
                    updated_at_utc=str(row["updated_at_utc"] or ""),
                )
            )
        return result

    def save_decision(
        self,
        case_key: str,
        decision: str,
        selected_pinyin: str = "",
        note: str = "",
        reviewer: str = "manual",
    ) -> None:
        self.save_decisions_batch(
            (
                {
                    "case_key": case_key,
                    "decision": decision,
                    "selected_pinyin": selected_pinyin,
                    "note": note,
                },
            ),
            reviewer=reviewer,
        )

    def save_decisions_batch(
        self,
        decisions: Sequence[Mapping[str, str]],
        *,
        reviewer: str = "batch-rule",
    ) -> int:
        """Persist a validated batch atomically and append one history row per case."""

        reviewer = reviewer.strip() or "batch-rule"
        prepared: list[dict[str, str]] = []
        seen_keys: set[str] = set()
        for item in decisions:
            case_key = str(item.get("case_key", "")).strip()
            decision = str(item.get("decision", "")).strip()
            selected_pinyin = str(item.get("selected_pinyin", "")).strip()
            note = str(item.get("note", "")).strip()
            if not case_key:
                raise ValueError("case_key is required")
            if case_key in seen_keys:
                raise ValueError(f"duplicate review case in batch: {case_key}")
            seen_keys.add(case_key)
            if decision not in VALID_REVIEW_DECISIONS:
                raise ValueError(f"unsupported review decision: {decision}")
            if decision in {"accept_psc", "keep_both"} and not selected_pinyin:
                raise ValueError("selected_pinyin is required for accept_psc or keep_both")
            if decision == "psc_evidence_error" and not note:
                raise ValueError(
                    "a note is required when marking PSC evidence as erroneous"
                )
            current_case = self.connection.execute(
                "SELECT case_key FROM review_cases WHERE case_key = ?", (case_key,)
            ).fetchone()
            if current_case is None:
                raise KeyError(f"review case is not active: {case_key}")
            prepared.append(
                {
                    "case_key": case_key,
                    "decision": decision,
                    "selected_pinyin": selected_pinyin,
                    "note": note,
                }
            )

        if not prepared:
            return 0

        now = _utc_now()
        with self.connection:
            for item in prepared:
                case_key = item["case_key"]
                previous = self.connection.execute(
                    "SELECT * FROM review_decisions WHERE case_key = ?", (case_key,)
                ).fetchone()
                decided_at = str(previous["decided_at_utc"]) if previous else now
                current = {
                    **item,
                    "reviewer": reviewer,
                    "decided_at_utc": decided_at,
                    "updated_at_utc": now,
                }
                self.connection.execute(
                    """
                    INSERT INTO review_decisions (
                        case_key, decision, selected_pinyin, note, reviewer,
                        decided_at_utc, updated_at_utc
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(case_key) DO UPDATE SET
                        decision = excluded.decision,
                        selected_pinyin = excluded.selected_pinyin,
                        note = excluded.note,
                        reviewer = excluded.reviewer,
                        updated_at_utc = excluded.updated_at_utc
                    """,
                    tuple(current.values()),
                )
                self.connection.execute(
                    """
                    INSERT INTO review_decision_history (
                        case_key, action, previous_json, current_json, occurred_at_utc
                    ) VALUES (?, 'save', ?, ?, ?)
                    """,
                    (
                        case_key,
                        json.dumps(dict(previous), ensure_ascii=False)
                        if previous
                        else None,
                        json.dumps(current, ensure_ascii=False),
                        now,
                    ),
                )
        return len(prepared)

    def clear_decision(self, case_key: str) -> None:
        previous = self.connection.execute(
            "SELECT * FROM review_decisions WHERE case_key = ?", (case_key,)
        ).fetchone()
        if previous is None:
            return
        now = _utc_now()
        with self.connection:
            self.connection.execute(
                "DELETE FROM review_decisions WHERE case_key = ?", (case_key,)
            )
            self.connection.execute(
                """
                INSERT INTO review_decision_history (
                    case_key, action, previous_json, current_json, occurred_at_utc
                ) VALUES (?, 'clear', ?, NULL, ?)
                """,
                (case_key, json.dumps(dict(previous), ensure_ascii=False), now),
            )

    def stats(self) -> dict[str, int]:
        stats = {"pending": 0, **{decision: 0 for decision in VALID_REVIEW_DECISIONS}}
        stats["pending"] = int(
            self.connection.execute(
                """
                SELECT COUNT(*) FROM review_cases AS c
                LEFT JOIN review_decisions AS d ON d.case_key = c.case_key
                WHERE d.case_key IS NULL
                """
            ).fetchone()[0]
        )
        for row in self.connection.execute(
            """
            SELECT d.decision, COUNT(*)
            FROM review_decisions AS d JOIN review_cases AS c ON c.case_key = d.case_key
            GROUP BY d.decision
            """
        ):
            stats[str(row[0])] = int(row[1])
        return stats


def _read_only_uri(path: Path) -> str:
    return f"{path.resolve().as_uri()}?mode=ro"


def _connect_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(_read_only_uri(path), uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    return connection


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _snapshot(path: Path) -> dict[str, object]:
    stat = path.stat()
    return {
        "path": str(path.resolve()),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "sha256": _sha256(path),
    }


def _assert_unchanged(path: Path, snapshot: dict[str, object]) -> None:
    stat = path.stat()
    current = (stat.st_size, stat.st_mtime_ns)
    expected = (snapshot["size"], snapshot["mtime_ns"])
    if current != expected:
        raise RuntimeError(f"input database changed while auditing: {path}")


def normalize_marked_pinyin(value: str) -> str:
    """Normalize marked Pinyin for comparison without inventing syllable splits."""

    normalized = unicodedata.normalize("NFC", str(value or "").strip().lower())
    normalized = normalized.replace("u:", "ü").replace("v", "ü")
    normalized = _IGNORED_PINYIN_RE.sub("", normalized)
    decomposed = unicodedata.normalize("NFD", normalized)
    if normalized and not any("a" <= char <= "z" for char in decomposed):
        return ""
    return normalized


def split_marked_variants(value: str) -> tuple[str, ...]:
    variants: list[str] = []
    for part in _ALT_SEPARATOR_RE.split(unicodedata.normalize("NFC", str(value or ""))):
        normalized = normalize_marked_pinyin(part)
        if normalized and normalized not in variants:
            variants.append(normalized)
    return tuple(variants)


def _has_non_er_suffix_r(variant: str) -> bool:
    base_letters = "".join(
        char for char in unicodedata.normalize("NFD", variant) if "a" <= char <= "z"
    )
    return base_letters.endswith("r") and not base_letters.endswith("er")


def _require_objects(connection: sqlite3.Connection, names: Iterable[str], label: str) -> None:
    available = {
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
        )
    }
    missing = sorted(set(names) - available)
    if missing:
        raise ValueError(f"{label} database is missing required objects: {missing}")


def load_psc_observations(connection: sqlite3.Connection) -> list[Observation]:
    _require_objects(
        connection,
        (
            "manually_reviewed_entries",
            "neutral_tone_entries",
            "erhua_entries",
            "rare_word_entries",
            "passage_pronunciation_entries",
        ),
        "PSC",
    )
    observations: list[Observation] = []

    for row in connection.execute(
        """
        SELECT table_number, source_index, reviewed_hanzi, reviewed_pinyin,
               page_number, column_number, review_decision
        FROM manually_reviewed_entries
        ORDER BY table_number, source_index
        """
    ):
        observations.append(
            Observation(
                "psc_main",
                f"{row['table_number']}:{row['source_index']}",
                int(row["source_index"]),
                str(row["reviewed_hanzi"] or "").strip(),
                str(row["reviewed_pinyin"] or "").strip(),
                {
                    "table_number": row["table_number"],
                    "source_index": row["source_index"],
                    "page_number": row["page_number"],
                    "column_number": row["column_number"],
                    "review_decision": row["review_decision"],
                },
            )
        )

    auxiliary_queries = (
        (
            "psc_neutral_tone",
            """
            SELECT id, source_index, hanzi AS text, pinyin_nfc AS pinyin,
                   page_number, table_order, row_order, pair_order
            FROM neutral_tone_entries ORDER BY source_index
            """,
        ),
        (
            "psc_erhua",
            """
            SELECT e.id, e.source_index, e.hanzi AS text, e.pinyin_nfc AS pinyin,
                   e.page_number, e.table_order, e.row_order, e.pair_order,
                   c.source_index AS category_index, c.rule_nfc AS category_rule
            FROM erhua_entries AS e
            JOIN erhua_categories AS c ON c.id = e.category_id
            ORDER BY e.source_index
            """,
        ),
        (
            "psc_rare_word",
            """
            SELECT e.id, e.source_index, e.hanzi AS text, e.pinyin_nfc AS pinyin,
                   e.sheet_name, e.source_row, e.pair_order,
                   g.group_label
            FROM rare_word_entries AS e
            JOIN rare_word_groups AS g ON g.id = e.group_id
            ORDER BY e.source_index
            """,
        ),
        (
            "psc_passage",
            """
            SELECT e.id, e.source_index, e.term AS text, e.pinyin_nfc AS pinyin,
                   e.entry_order, e.source_item_no, e.source_item_occurrence,
                   e.review_status, p.work_no, p.title, p.pdf_page_number
            FROM passage_pronunciation_entries AS e
            JOIN passage_pronunciation_passages AS p ON p.id = e.passage_id
            ORDER BY e.source_index
            """,
        ),
    )
    for source_kind, query in auxiliary_queries:
        for row in connection.execute(query):
            locator = {key: row[key] for key in row.keys() if key not in {"text", "pinyin"}}
            observations.append(
                Observation(
                    source_kind,
                    str(row["source_index"]),
                    int(row["source_index"]),
                    str(row["text"] or "").strip(),
                    str(row["pinyin"] or "").strip(),
                    locator,
                )
            )
    return observations


def _chunks(values: Sequence[str], size: int = 400) -> Iterator[Sequence[str]]:
    for offset in range(0, len(values), size):
        yield values[offset : offset + size]


def load_source_readings(
    connection: sqlite3.Connection,
    texts: Iterable[str],
) -> tuple[dict[str, list[Reading]], dict[str, list[Reading]]]:
    _require_objects(connection, ("canonical_readings", "accepted_readings"), "source")
    unique_texts = sorted({text for text in texts if text})
    canonical: dict[str, list[Reading]] = defaultdict(list)
    accepted: dict[str, list[Reading]] = defaultdict(list)
    for chunk in _chunks(unique_texts):
        placeholders = ",".join("?" for _ in chunk)
        for row in connection.execute(
            f"""
            SELECT text, marked_pinyin, numeric_pinyin, reading_rank, is_primary,
                   pinyin_sources, neutral_tone_status
            FROM canonical_readings WHERE text IN ({placeholders})
            ORDER BY text, reading_rank, marked_pinyin
            """,
            tuple(chunk),
        ):
            canonical[str(row["text"])].append(
                Reading(
                    str(row["marked_pinyin"]),
                    str(row["numeric_pinyin"]),
                    normalize_marked_pinyin(str(row["marked_pinyin"])),
                    bool(row["is_primary"]),
                    int(row["reading_rank"]),
                    str(row["pinyin_sources"]),
                    str(row["neutral_tone_status"]),
                )
            )
        for row in connection.execute(
            f"""
            SELECT text, marked, numeric, source_rank, source_primary, source,
                   neutral_tone_status
            FROM accepted_readings WHERE text IN ({placeholders})
            ORDER BY text, source_rank, marked, source
            """,
            tuple(chunk),
        ):
            accepted[str(row["text"])].append(
                Reading(
                    str(row["marked"]),
                    str(row["numeric"]),
                    normalize_marked_pinyin(str(row["marked"])),
                    bool(row["source_primary"]),
                    int(row["source_rank"]),
                    str(row["source"]),
                    str(row["neutral_tone_status"]),
                )
            )
    return dict(canonical), dict(accepted)


def _base_outcome(
    variants: tuple[str, ...],
    canonical: tuple[Reading, ...],
    accepted: tuple[Reading, ...],
) -> tuple[str, tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    canonical_set = {reading.normalized for reading in canonical}
    primary_set = {reading.normalized for reading in canonical if reading.is_primary}
    accepted_set = {reading.normalized for reading in accepted}
    matched_canonical = tuple(item for item in variants if item in canonical_set)
    matched_accepted = tuple(item for item in variants if item in accepted_set)
    unmatched = tuple(item for item in variants if item not in canonical_set)
    if not variants:
        outcome = "invalid_psc_evidence"
    elif len(matched_canonical) == len(variants):
        outcome = "exact_primary" if primary_set.intersection(variants) else "exact_alternate"
    elif len(matched_accepted) == len(variants):
        outcome = "accepted_source_only"
    elif matched_canonical or matched_accepted:
        outcome = "partial_match"
    elif not canonical and not accepted:
        outcome = "missing_source_text"
    else:
        outcome = "pronunciation_conflict"
    return outcome, matched_canonical, matched_accepted, unmatched


def classify_observation(
    observation: Observation,
    canonical_readings: Iterable[Reading],
    accepted_readings: Iterable[Reading],
    *,
    known_neutral_evidence: bool = False,
    known_erhua_evidence: bool = False,
) -> AuditResult:
    variants = split_marked_variants(observation.pinyin_raw)
    canonical = tuple(canonical_readings)
    accepted = tuple(accepted_readings)
    outcome, matched_canonical, matched_accepted, unmatched = _base_outcome(
        variants, canonical, accepted
    )

    attached_erhua = any(_has_non_er_suffix_r(variant) for variant in variants)
    if not observation.text or not variants:
        lane, priority = "invalid_psc_evidence_review", 120
    elif observation.source_kind == "psc_erhua" or known_erhua_evidence or attached_erhua:
        lane, priority = "erhua_policy_review", 80
        outcome = "erhua_policy_review"
    elif outcome == "exact_primary":
        lane, priority = "verified", 0
    elif observation.source_kind == "psc_neutral_tone" or known_neutral_evidence:
        lane, priority = "neutral_tone_review", 90
    elif observation.source_kind == "psc_rare_word":
        lane, priority = "supplemental_reference_review", 50
    elif observation.source_kind == "psc_passage":
        lane, priority = "contextual_reference_review", 40
    elif outcome == "exact_alternate":
        lane, priority = "primary_ranking_review", 75
    elif outcome == "accepted_source_only":
        lane, priority = "canonical_promotion_review", 95
    elif outcome == "missing_source_text":
        lane, priority = "missing_source_text_review", 105
    else:
        lane, priority = "canonical_pronunciation_review", 110

    explanations = {
        "exact_primary": "PSC 拼音与原型主读音一致。",
        "exact_alternate": "PSC 拼音仅与原型次读音一致，需复核主读音排序。",
        "accepted_source_only": "PSC 拼音存在于来源证据层，但未进入规范读音层。",
        "partial_match": "PSC 多读形式仅有一部分可在原型来源中找到。",
        "missing_source_text": "原型规范读音层和来源证据层均无该词形。",
        "pronunciation_conflict": "原型存在该词形，但没有与 PSC 一致的读音。",
        "invalid_psc_evidence": "PSC 记录缺少可比较的词形或拼音。",
        "erhua_policy_review": "儿化记音与字音节对齐不同，保留为儿化政策证据，不自动覆盖规范读音。",
    }
    return AuditResult(
        outcome,
        lane,
        priority,
        variants,
        canonical,
        accepted,
        matched_canonical,
        matched_accepted,
        unmatched,
        explanations[outcome],
    )


def _reading_payload(readings: Iterable[Reading]) -> str:
    rows = [
        {
            "marked": item.marked,
            "numeric": item.numeric,
            "is_primary": item.is_primary,
            "reading_rank": item.reading_rank,
            "sources": item.sources,
            "neutral_tone_status": item.neutral_tone_status,
        }
        for item in readings
    ]
    return json.dumps(rows, ensure_ascii=False, separators=(",", ":"))


def _create_output_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA journal_mode = DELETE;
        PRAGMA foreign_keys = ON;
        CREATE TABLE audit_run (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version TEXT NOT NULL,
            generated_at_utc TEXT NOT NULL,
            source_db_json TEXT NOT NULL,
            psc_db_json TEXT NOT NULL,
            policy_json TEXT NOT NULL
        );
        CREATE TABLE observations (
            id INTEGER PRIMARY KEY,
            source_kind TEXT NOT NULL,
            source_key TEXT NOT NULL,
            source_order INTEGER NOT NULL,
            evidence_role TEXT NOT NULL,
            text TEXT NOT NULL,
            pinyin_raw TEXT NOT NULL,
            pinyin_variants_json TEXT NOT NULL,
            locator_json TEXT NOT NULL,
            UNIQUE(source_kind, source_key)
        );
        CREATE TABLE audit_results (
            observation_id INTEGER PRIMARY KEY
                REFERENCES observations(id) ON DELETE CASCADE,
            outcome TEXT NOT NULL,
            review_lane TEXT NOT NULL,
            review_priority INTEGER NOT NULL,
            canonical_readings_json TEXT NOT NULL,
            accepted_readings_json TEXT NOT NULL,
            matched_canonical_json TEXT NOT NULL,
            matched_accepted_json TEXT NOT NULL,
            unmatched_variants_json TEXT NOT NULL,
            explanation TEXT NOT NULL
        );
        CREATE INDEX audit_results_lane_idx
            ON audit_results(review_lane, review_priority DESC, observation_id);
        CREATE TABLE review_cases (
            case_key TEXT PRIMARY KEY,
            review_lane TEXT NOT NULL,
            review_priority INTEGER NOT NULL,
            text TEXT NOT NULL,
            pinyin_forms_json TEXT NOT NULL,
            pinyin_variants_json TEXT NOT NULL,
            outcomes_json TEXT NOT NULL,
            evidence_sources_json TEXT NOT NULL,
            evidence_count INTEGER NOT NULL,
            representative_observation_id INTEGER NOT NULL
                REFERENCES observations(id) ON DELETE CASCADE,
            canonical_readings_json TEXT NOT NULL,
            accepted_readings_json TEXT NOT NULL,
            unmatched_variants_json TEXT NOT NULL,
            evidence_items_json TEXT NOT NULL,
            explanation TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE INDEX review_cases_order_idx
            ON review_cases(review_priority DESC, review_lane, text, case_key);
        CREATE TABLE review_decisions (
            case_key TEXT PRIMARY KEY,
            decision TEXT NOT NULL CHECK (
                decision IN (
                    'accept_psc', 'keep_source', 'keep_both',
                    'psc_evidence_error', 'defer'
                )
            ),
            selected_pinyin TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            reviewer TEXT NOT NULL DEFAULT 'manual',
            decided_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE review_decision_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            case_key TEXT NOT NULL,
            action TEXT NOT NULL CHECK (action IN ('save', 'clear')),
            previous_json TEXT,
            current_json TEXT,
            occurred_at_utc TEXT NOT NULL
        );
        CREATE INDEX review_decision_history_case_idx
            ON review_decision_history(case_key, occurred_at_utc, id);
        CREATE VIEW audit_detail AS
        SELECT o.id, o.source_kind, o.source_key, o.source_order,
               o.evidence_role, o.text, o.pinyin_raw, o.pinyin_variants_json,
               o.locator_json, r.outcome, r.review_lane, r.review_priority,
               r.canonical_readings_json, r.accepted_readings_json,
               r.matched_canonical_json, r.matched_accepted_json,
               r.unmatched_variants_json, r.explanation
        FROM observations AS o JOIN audit_results AS r ON r.observation_id = o.id;
        CREATE VIEW review_evidence_queue AS
        SELECT * FROM audit_detail
        WHERE review_lane <> 'verified'
        ORDER BY review_priority DESC, source_kind, source_order, id;
        CREATE VIEW review_case_detail AS
        SELECT c.*, d.decision, d.selected_pinyin, d.note, d.reviewer,
               d.decided_at_utc, d.updated_at_utc
        FROM review_cases AS c
        LEFT JOIN review_decisions AS d ON d.case_key = c.case_key;
        CREATE VIEW consolidated_review_queue AS
        SELECT * FROM review_case_detail
        ORDER BY review_priority DESC, review_lane, text, case_key;
        CREATE VIEW review_queue AS
        SELECT * FROM review_case_detail
        WHERE decision IS NULL
        ORDER BY review_priority DESC, review_lane, text, case_key;
        CREATE VIEW reviewed_cases AS
        SELECT * FROM review_case_detail
        WHERE decision IS NOT NULL
        ORDER BY updated_at_utc DESC, review_priority DESC, text, case_key;
        CREATE VIEW orphaned_review_decisions AS
        SELECT d.* FROM review_decisions AS d
        LEFT JOIN review_cases AS c ON c.case_key = d.case_key
        WHERE c.case_key IS NULL
        ORDER BY d.updated_at_utc DESC, d.case_key;
        CREATE VIEW audit_summary AS
        SELECT o.source_kind, r.outcome, r.review_lane, COUNT(*) AS record_count
        FROM observations AS o JOIN audit_results AS r ON r.observation_id = o.id
        GROUP BY o.source_kind, r.outcome, r.review_lane
        ORDER BY o.source_kind, r.review_lane, r.outcome;
        """
    )


def _write_review_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    columns = (
        "case_key",
        "review_priority",
        "review_lane",
        "evidence_count",
        "evidence_sources",
        "source_kind",
        "source_key",
        "text",
        "pinyin_raw",
        "outcome",
        "canonical_marked",
        "canonical_numeric",
        "unmatched_variants",
        "explanation",
        "decision",
        "selected_pinyin",
        "decision_note",
        "reviewer",
        "decision_updated_at_utc",
        "locator_json",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def _markdown_table(counter: Counter[tuple[str, str]]) -> list[str]:
    lines = ["| 来源 | 结果 | 数量 |", "|---|---|---:|"]
    for (source_kind, value), count in sorted(counter.items()):
        lines.append(f"| {SOURCE_POLICY[source_kind]['label']} | `{value}` | {count} |")
    return lines


def _load_existing_review_state(
    database: Path,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    if not database.is_file():
        return [], []
    connection = _connect_read_only(database)
    try:
        names = {
            str(row[0])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        if "review_decisions" not in names or "review_decision_history" not in names:
            return [], []
        decisions = [
            dict(row)
            for row in connection.execute(
                "SELECT * FROM review_decisions ORDER BY case_key"
            )
        ]
        history = [
            dict(row)
            for row in connection.execute(
                "SELECT * FROM review_decision_history ORDER BY id"
            )
        ]
        return decisions, history
    finally:
        connection.close()


def run_audit(source_db: Path, psc_db: Path, output_dir: Path) -> AuditArtifacts:
    source_db = source_db.resolve()
    psc_db = psc_db.resolve()
    output_dir = output_dir.resolve()
    for path, label in ((source_db, "source"), (psc_db, "PSC")):
        if not path.is_file():
            raise FileNotFoundError(f"{label} database not found: {path}")

    source_snapshot = _snapshot(source_db)
    psc_snapshot = _snapshot(psc_db)
    psc_connection = _connect_read_only(psc_db)
    try:
        observations = load_psc_observations(psc_connection)
    finally:
        psc_connection.close()
    source_connection = _connect_read_only(source_db)
    try:
        canonical_by_text, accepted_by_text = load_source_readings(
            source_connection, (item.text for item in observations)
        )
    finally:
        source_connection.close()

    classified: list[tuple[Observation, AuditResult]] = []
    neutral_pairs = {
        (item.text, variant)
        for item in observations
        if item.source_kind == "psc_neutral_tone"
        for variant in split_marked_variants(item.pinyin_raw)
    }
    erhua_texts = {
        item.text for item in observations if item.source_kind == "psc_erhua"
    }
    for observation in observations:
        observation_variants = split_marked_variants(observation.pinyin_raw)
        classified.append(
            (
                observation,
                classify_observation(
                    observation,
                    canonical_by_text.get(observation.text, ()),
                    accepted_by_text.get(observation.text, ()),
                    known_neutral_evidence=any(
                        (observation.text, variant) in neutral_pairs
                        for variant in observation_variants
                    ),
                    known_erhua_evidence=(
                        observation.text in erhua_texts
                        and any(variant.endswith("r") for variant in observation_variants)
                    ),
                ),
            )
        )

    outcome_counts = Counter(
        (observation.source_kind, result.outcome) for observation, result in classified
    )
    lane_counts = Counter(
        (observation.source_kind, result.review_lane) for observation, result in classified
    )
    source_counts = Counter(observation.source_kind for observation, _ in classified)
    review_observation_count = sum(
        result.review_lane != "verified" for _, result in classified
    )
    review_case_groups: dict[
        tuple[str, str, tuple[str, ...]],
        list[tuple[int, Observation, AuditResult]],
    ] = defaultdict(list)
    for observation_id, (observation, result) in enumerate(classified, start=1):
        if result.review_lane != "verified":
            key = (result.review_lane, observation.text, result.psc_variants)
            review_case_groups[key].append((observation_id, observation, result))
    review_case_count = len(review_case_groups)

    _assert_unchanged(source_db, source_snapshot)
    _assert_unchanged(psc_db, psc_snapshot)
    output_dir.mkdir(parents=True, exist_ok=True)
    database = output_dir / "psc_pronunciation_audit.sqlite3"
    existing_decisions, existing_history = _load_existing_review_state(database)
    temp_database = output_dir / f".{database.name}.{os.getpid()}.tmp"
    if temp_database.exists():
        temp_database.unlink()
    generated_at = datetime.now(timezone.utc).isoformat()
    output = sqlite3.connect(temp_database)
    try:
        _create_output_schema(output)
        output.execute(
            "INSERT INTO audit_run VALUES (1, ?, ?, ?, ?, ?)",
            (
                SCHEMA_VERSION,
                generated_at,
                json.dumps(source_snapshot, ensure_ascii=False, separators=(",", ":")),
                json.dumps(psc_snapshot, ensure_ascii=False, separators=(",", ":")),
                json.dumps(SOURCE_POLICY, ensure_ascii=False, separators=(",", ":")),
            ),
        )
        for observation_id, (observation, result) in enumerate(classified, start=1):
            output.execute(
                """
                INSERT INTO observations (
                    id, source_kind, source_key, source_order, evidence_role,
                    text, pinyin_raw, pinyin_variants_json, locator_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    observation_id,
                    observation.source_kind,
                    observation.source_key,
                    observation.source_order,
                    SOURCE_POLICY[observation.source_kind]["evidence_role"],
                    observation.text,
                    observation.pinyin_raw,
                    json.dumps(result.psc_variants, ensure_ascii=False),
                    json.dumps(observation.locator, ensure_ascii=False, separators=(",", ":")),
                ),
            )
            output.execute(
                """
                INSERT INTO audit_results VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    observation_id,
                    result.outcome,
                    result.review_lane,
                    result.review_priority,
                    _reading_payload(result.canonical_readings),
                    _reading_payload(result.accepted_readings),
                    json.dumps(result.matched_canonical, ensure_ascii=False),
                    json.dumps(result.matched_accepted, ensure_ascii=False),
                    json.dumps(result.unmatched, ensure_ascii=False),
                    result.explanation,
                ),
            )
        for (review_lane, text, variants), items in review_case_groups.items():
            representative_id, representative, result = items[0]
            case_key = _review_case_key(review_lane, text, variants)
            pinyin_forms = list(
                dict.fromkeys(item_observation.pinyin_raw for _, item_observation, _ in items)
            )
            outcomes = sorted({item_result.outcome for _, _, item_result in items})
            evidence_sources = sorted(
                {item_observation.source_kind for _, item_observation, _ in items}
            )
            evidence_items = [
                {
                    "observation_id": observation_id,
                    "source_kind": item_observation.source_kind,
                    "source_key": item_observation.source_key,
                    "pinyin_raw": item_observation.pinyin_raw,
                    "outcome": item_result.outcome,
                    "locator": item_observation.locator,
                }
                for observation_id, item_observation, item_result in items
            ]
            output.execute(
                """
                INSERT INTO review_cases (
                    case_key, review_lane, review_priority, text,
                    pinyin_forms_json, pinyin_variants_json, outcomes_json,
                    evidence_sources_json, evidence_count,
                    representative_observation_id, canonical_readings_json,
                    accepted_readings_json, unmatched_variants_json,
                    evidence_items_json, explanation
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    case_key,
                    review_lane,
                    max(item_result.review_priority for _, _, item_result in items),
                    text,
                    json.dumps(pinyin_forms, ensure_ascii=False),
                    json.dumps(variants, ensure_ascii=False),
                    json.dumps(outcomes, ensure_ascii=False),
                    json.dumps(evidence_sources, ensure_ascii=False),
                    len(items),
                    representative_id,
                    _reading_payload(result.canonical_readings),
                    _reading_payload(result.accepted_readings),
                    json.dumps(result.unmatched, ensure_ascii=False),
                    json.dumps(evidence_items, ensure_ascii=False, separators=(",", ":")),
                    result.explanation,
                ),
            )
        for decision in existing_decisions:
            output.execute(
                """
                INSERT INTO review_decisions (
                    case_key, decision, selected_pinyin, note, reviewer,
                    decided_at_utc, updated_at_utc
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    decision["case_key"],
                    decision["decision"],
                    decision["selected_pinyin"],
                    decision["note"],
                    decision["reviewer"],
                    decision["decided_at_utc"],
                    decision["updated_at_utc"],
                ),
            )
        for history in existing_history:
            output.execute(
                """
                INSERT INTO review_decision_history (
                    id, case_key, action, previous_json, current_json, occurred_at_utc
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    history["id"],
                    history["case_key"],
                    history["action"],
                    history["previous_json"],
                    history["current_json"],
                    history["occurred_at_utc"],
                ),
            )
        integrity = output.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"audit database integrity check failed: {integrity}")
        output.commit()
    finally:
        output.close()
    os.replace(temp_database, database)
    completed = sqlite3.connect(database)
    try:
        decided_case_count = int(
            completed.execute(
                """
                SELECT COUNT(*) FROM review_decisions AS d
                JOIN review_cases AS c ON c.case_key = d.case_key
                """
            ).fetchone()[0]
        )
    finally:
        completed.close()
    pending_case_count = review_case_count - decided_case_count
    summary = {
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": generated_at,
        "inputs": {"source_db": source_snapshot, "psc_db": psc_snapshot},
        "counts": {
            "observations": len(classified),
            "verified": len(classified) - review_observation_count,
            "needs_review": review_observation_count,
            "review_cases": review_case_count,
            "pending_review_cases": pending_case_count,
            "decided_review_cases": decided_case_count,
            "by_source": dict(sorted(source_counts.items())),
            "by_source_and_outcome": {
                f"{source}:{outcome}": count
                for (source, outcome), count in sorted(outcome_counts.items())
            },
            "by_source_and_review_lane": {
                f"{source}:{lane}": count
                for (source, lane), count in sorted(lane_counts.items())
            },
        },
        "safeguards": {
            "source_lexicon_opened_read_only": True,
            "psc_database_opened_read_only": True,
            "canonical_readings_modified": False,
            "automatic_corrections_applied": 0,
            "erhua_never_auto_promoted": True,
            "contextual_evidence_never_auto_promoted": True,
        },
    }
    summary_json = output_dir / "summary.json"
    summary_json.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    review_rows: list[dict[str, object]] = []
    decision_by_case = {
        str(decision["case_key"]): decision for decision in existing_decisions
    }
    sorted_cases = sorted(
        review_case_groups.values(),
        key=lambda items: (
            -max(item[2].review_priority for item in items),
            items[0][2].review_lane,
            items[0][1].text,
            items[0][1].source_order,
        ),
    )
    for items in sorted_cases:
        _, observation, result = items[0]
        case_key = _review_case_key(result.review_lane, observation.text, result.psc_variants)
        decision = decision_by_case.get(case_key, {})
        evidence_sources = sorted({item[1].source_kind for item in items})
        review_rows.append(
            {
                "case_key": case_key,
                "review_priority": result.review_priority,
                "review_lane": result.review_lane,
                "evidence_count": len(items),
                "evidence_sources": ",".join(evidence_sources),
                "source_kind": observation.source_kind,
                "source_key": observation.source_key,
                "text": observation.text,
                "pinyin_raw": observation.pinyin_raw,
                "outcome": result.outcome,
                "canonical_marked": " / ".join(
                    item.marked for item in result.canonical_readings
                ),
                "canonical_numeric": " / ".join(
                    item.numeric for item in result.canonical_readings
                ),
                "unmatched_variants": " / ".join(result.unmatched),
                "explanation": result.explanation,
                "decision": decision.get("decision", ""),
                "selected_pinyin": decision.get("selected_pinyin", ""),
                "decision_note": decision.get("note", ""),
                "reviewer": decision.get("reviewer", ""),
                "decision_updated_at_utc": decision.get("updated_at_utc", ""),
                "locator_json": json.dumps(
                    [
                        {
                            "source_kind": item_observation.source_kind,
                            "source_key": item_observation.source_key,
                            "locator": item_observation.locator,
                        }
                        for _, item_observation, _ in items
                    ],
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
            }
        )
    review_tsv = output_dir / "review_queue.tsv"
    _write_review_tsv(review_tsv, review_rows)

    report_lines = [
        "# PSC 2021/2024 规范读音真源审计",
        "",
        f"- 生成时间：`{generated_at}`",
        f"- 对照记录：**{len(classified)}**",
        f"- 自动确认一致：**{len(classified) - review_observation_count}**",
        f"- 待复核证据记录：**{review_observation_count}**",
        f"- 合并后的人工复核事项：**{review_case_count}**",
        f"- 尚未裁决：**{pending_case_count}**",
        f"- 已持久化裁决：**{decided_case_count}**",
        "- 自动改写真源：**0**",
        "",
        "## 结果分布",
        "",
        *_markdown_table(outcome_counts),
        "",
        "## 复核通道",
        "",
        *_markdown_table(lane_counts),
        "",
        "## 边界",
        "",
        "- 主词表的不一致项可作为规范读音修订候选，但仍须人工裁决。",
        "- 必读轻声表只校验词汇固有轻声，不推导语境轻声。",
        "- 儿化表只作儿化表示政策证据，不自动改写字音节对齐或基础编码。",
        "- 生僻字表与朗读提示只作补充或语境证据，不自动提升为规范主读音。",
        "- 两个输入数据库均以 SQLite 只读模式打开；审计结果写入独立数据库。",
        "",
    ]
    report_markdown = output_dir / "REPORT.md"
    report_markdown.write_text("\n".join(report_lines), encoding="utf-8")
    return AuditArtifacts(
        database,
        summary_json,
        report_markdown,
        review_tsv,
        len(classified),
        review_observation_count,
        review_case_count,
        pending_case_count,
        decided_case_count,
    )


__all__ = [
    "AuditArtifacts",
    "AuditResult",
    "Observation",
    "Reading",
    "ReviewCase",
    "ReviewDecisionStore",
    "VALID_REVIEW_DECISIONS",
    "classify_observation",
    "load_psc_observations",
    "load_source_readings",
    "normalize_marked_pinyin",
    "run_audit",
    "split_marked_variants",
]
