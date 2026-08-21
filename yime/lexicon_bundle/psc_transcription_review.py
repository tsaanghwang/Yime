"""Persistent first-stage review of PSC source transcriptions.

This module deliberately does not adjudicate canonical pronunciations.  It reads
the generated PSC comparison database, then stores only decisions about whether
the transcribed Hanzi--Pinyin pair agrees with the source material.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


VALID_TRANSCRIPTION_DECISIONS = frozenset({"confirmed", "corrected", "unresolved"})


def next_visible_key_after_save(
    previous_keys: Sequence[str],
    current_key: str | None,
    refreshed_keys: Sequence[str],
) -> str | None:
    """Choose the next visible record after saving the current one.

    A save may either leave the current record in the active filter (for
    example, when viewing all states) or remove it (when viewing only pending
    records).  Prefer the next record from the pre-save ordering in both cases,
    wrapping at the end.  If the refresh has replaced the whole queue, fall
    back to the same ordinal position in the refreshed list.
    """

    if not refreshed_keys:
        return None
    if not previous_keys or current_key not in previous_keys:
        return refreshed_keys[0]

    refreshed = set(refreshed_keys)
    current_index = previous_keys.index(current_key)
    for offset in range(1, len(previous_keys) + 1):
        candidate = previous_keys[(current_index + offset) % len(previous_keys)]
        if candidate in refreshed:
            return candidate

    return refreshed_keys[min(current_index, len(refreshed_keys) - 1)]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _record_fingerprint(source_kind: str, source_key: str, text: str, pinyin: str) -> str:
    payload = "\0".join((source_kind, source_key, text, pinyin)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _connect_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    connection.execute("PRAGMA busy_timeout = 5000")
    return connection


@dataclass(frozen=True)
class TranscriptionReviewItem:
    source_kind: str
    source_key: str
    source_order: int
    text: str
    pinyin: str
    locator: dict[str, object]
    review_lane: str
    review_priority: int
    canonical_readings: tuple[dict[str, object], ...]
    accepted_readings: tuple[dict[str, object], ...]
    explanation: str
    decision: str = "pending"
    corrected_text: str = ""
    corrected_pinyin: str = ""
    note: str = ""
    reviewer: str = ""
    updated_at_utc: str = ""
    stale_decision: bool = False

    @property
    def record_key(self) -> str:
        return f"{self.source_kind}:{self.source_key}"

    @property
    def needs_reference_check(self) -> bool:
        return self.review_lane != "verified"

    @property
    def review_state(self) -> str:
        """Return the derived first-stage state shown by the review UI.

        ``verified`` audit rows are machine matches, not manual decisions.  Keep
        them out of the writable decision ledger while making that distinction
        explicit instead of presenting them as pending manual work.
        """

        if self.stale_decision:
            return "stale"
        if self.decision == "pending" and not self.needs_reference_check:
            return "machine_verified"
        return self.decision

    @property
    def effective_text(self) -> str:
        if self.decision == "corrected" and not self.stale_decision:
            return self.corrected_text
        return self.text

    @property
    def effective_pinyin(self) -> str:
        if self.decision == "corrected" and not self.stale_decision:
            return self.corrected_pinyin
        return self.pinyin


class TranscriptionReviewStore:
    """Read comparison results and write only a separate transcription ledger."""

    def __init__(self, audit_database: Path, decision_database: Path | None = None) -> None:
        self.audit_database = audit_database.resolve()
        if not self.audit_database.is_file():
            raise FileNotFoundError(f"PSC audit database not found: {self.audit_database}")
        self.decision_database = (
            decision_database.resolve()
            if decision_database
            else self.audit_database.with_name("psc_transcription_review.sqlite3")
        )
        self.audit = _connect_read_only(self.audit_database)
        self.decision_database.parent.mkdir(parents=True, exist_ok=True)
        self.decisions = sqlite3.connect(self.decision_database)
        self.decisions.row_factory = sqlite3.Row
        self.decisions.execute("PRAGMA foreign_keys = ON")
        self.decisions.execute("PRAGMA busy_timeout = 5000")
        self._create_schema()

    def _create_schema(self) -> None:
        with self.decisions:
            self.decisions.executescript(
                """
                CREATE TABLE IF NOT EXISTS review_metadata (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS transcription_decisions (
                    source_kind TEXT NOT NULL,
                    source_key TEXT NOT NULL,
                    source_text TEXT NOT NULL,
                    source_pinyin TEXT NOT NULL,
                    source_fingerprint TEXT NOT NULL,
                    decision TEXT NOT NULL CHECK (
                        decision IN ('confirmed', 'corrected', 'unresolved')
                    ),
                    corrected_text TEXT NOT NULL DEFAULT '',
                    corrected_pinyin TEXT NOT NULL DEFAULT '',
                    note TEXT NOT NULL DEFAULT '',
                    reviewer TEXT NOT NULL DEFAULT 'manual',
                    decided_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (source_kind, source_key)
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS transcription_decision_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_kind TEXT NOT NULL,
                    source_key TEXT NOT NULL,
                    action TEXT NOT NULL CHECK (action IN ('save', 'clear')),
                    previous_json TEXT,
                    current_json TEXT,
                    occurred_at_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS transcription_history_record_idx
                    ON transcription_decision_history(
                        source_kind, source_key, occurred_at_utc, id
                    );
                """
            )
            self.decisions.execute(
                "INSERT OR REPLACE INTO review_metadata(key, value) VALUES (?, ?)",
                ("workflow", "psc-source-transcription-review-v1"),
            )

    def close(self) -> None:
        self.audit.close()
        self.decisions.close()

    def audit_inputs(self) -> dict[str, dict[str, object]]:
        row = self.audit.execute(
            "SELECT source_db_json, psc_db_json FROM audit_run WHERE id=1"
        ).fetchone()
        if row is None:
            raise ValueError("audit_run metadata is missing")
        return {
            "prototype": dict(json.loads(str(row["source_db_json"]))),
            "source_material": dict(json.loads(str(row["psc_db_json"]))),
        }

    def load_items(self) -> list[TranscriptionReviewItem]:
        rows = self.audit.execute(
            """
            SELECT source_kind, source_key, source_order, text, pinyin_raw,
                   locator_json, review_lane, review_priority,
                   canonical_readings_json, accepted_readings_json, explanation
              FROM audit_detail
             ORDER BY source_kind, source_order, id
            """
        ).fetchall()
        decisions = {
            (str(row["source_kind"]), str(row["source_key"])): row
            for row in self.decisions.execute("SELECT * FROM transcription_decisions")
        }
        items: list[TranscriptionReviewItem] = []
        for row in rows:
            source_kind = str(row["source_kind"])
            source_key = str(row["source_key"])
            text = str(row["text"] or "")
            pinyin = str(row["pinyin_raw"] or "")
            item = TranscriptionReviewItem(
                source_kind=source_kind,
                source_key=source_key,
                source_order=int(row["source_order"]),
                text=text,
                pinyin=pinyin,
                locator=dict(json.loads(str(row["locator_json"]))),
                review_lane=str(row["review_lane"]),
                review_priority=int(row["review_priority"]),
                canonical_readings=tuple(json.loads(str(row["canonical_readings_json"]))),
                accepted_readings=tuple(json.loads(str(row["accepted_readings_json"]))),
                explanation=str(row["explanation"]),
            )
            saved = decisions.get((source_kind, source_key))
            if saved is not None:
                fingerprint = _record_fingerprint(source_kind, source_key, text, pinyin)
                stale = str(saved["source_fingerprint"]) != fingerprint
                item = replace(
                    item,
                    decision="pending" if stale else str(saved["decision"]),
                    corrected_text=str(saved["corrected_text"] or ""),
                    corrected_pinyin=str(saved["corrected_pinyin"] or ""),
                    note=str(saved["note"] or ""),
                    reviewer=str(saved["reviewer"] or ""),
                    updated_at_utc=str(saved["updated_at_utc"] or ""),
                    stale_decision=stale,
                )
            items.append(item)
        return items

    def save(
        self,
        item: TranscriptionReviewItem,
        decision: str,
        corrected_text: str,
        corrected_pinyin: str,
        note: str = "",
        reviewer: str = "manual",
    ) -> None:
        decision = decision.strip()
        corrected_text = corrected_text.strip()
        corrected_pinyin = corrected_pinyin.strip()
        note = note.strip()
        reviewer = reviewer.strip() or "manual"
        if decision not in VALID_TRANSCRIPTION_DECISIONS:
            raise ValueError(f"unsupported transcription decision: {decision}")
        if decision in {"confirmed", "corrected"} and (
            not corrected_text or not corrected_pinyin
        ):
            raise ValueError("both corrected_text and corrected_pinyin are required")
        if decision == "confirmed" and (
            corrected_text != item.text or corrected_pinyin != item.pinyin
        ):
            raise ValueError("confirmed transcription must equal the extracted record")
        if decision == "corrected" and (
            corrected_text == item.text and corrected_pinyin == item.pinyin
        ):
            raise ValueError("corrected transcription must change text or pinyin")

        previous = self.decisions.execute(
            "SELECT * FROM transcription_decisions WHERE source_kind=? AND source_key=?",
            (item.source_kind, item.source_key),
        ).fetchone()
        now = _utc_now()
        current = {
            "source_kind": item.source_kind,
            "source_key": item.source_key,
            "source_text": item.text,
            "source_pinyin": item.pinyin,
            "source_fingerprint": _record_fingerprint(
                item.source_kind, item.source_key, item.text, item.pinyin
            ),
            "decision": decision,
            "corrected_text": corrected_text,
            "corrected_pinyin": corrected_pinyin,
            "note": note,
            "reviewer": reviewer,
            "decided_at_utc": str(previous["decided_at_utc"]) if previous else now,
            "updated_at_utc": now,
        }
        with self.decisions:
            self.decisions.execute(
                """
                INSERT INTO transcription_decisions(
                    source_kind, source_key, source_text, source_pinyin,
                    source_fingerprint, decision, corrected_text,
                    corrected_pinyin, note, reviewer, decided_at_utc, updated_at_utc
                ) VALUES (
                    :source_kind, :source_key, :source_text, :source_pinyin,
                    :source_fingerprint, :decision, :corrected_text,
                    :corrected_pinyin, :note, :reviewer, :decided_at_utc,
                    :updated_at_utc
                )
                ON CONFLICT(source_kind, source_key) DO UPDATE SET
                    source_text=excluded.source_text,
                    source_pinyin=excluded.source_pinyin,
                    source_fingerprint=excluded.source_fingerprint,
                    decision=excluded.decision,
                    corrected_text=excluded.corrected_text,
                    corrected_pinyin=excluded.corrected_pinyin,
                    note=excluded.note,
                    reviewer=excluded.reviewer,
                    updated_at_utc=excluded.updated_at_utc
                """,
                current,
            )
            self.decisions.execute(
                """
                INSERT INTO transcription_decision_history(
                    source_kind, source_key, action, previous_json,
                    current_json, occurred_at_utc
                ) VALUES (?, ?, 'save', ?, ?, ?)
                """,
                (
                    item.source_kind,
                    item.source_key,
                    json.dumps(dict(previous), ensure_ascii=False) if previous else None,
                    json.dumps(current, ensure_ascii=False),
                    now,
                ),
            )

    def clear(self, item: TranscriptionReviewItem) -> None:
        previous = self.decisions.execute(
            "SELECT * FROM transcription_decisions WHERE source_kind=? AND source_key=?",
            (item.source_kind, item.source_key),
        ).fetchone()
        if previous is None:
            return
        now = _utc_now()
        with self.decisions:
            self.decisions.execute(
                "DELETE FROM transcription_decisions WHERE source_kind=? AND source_key=?",
                (item.source_kind, item.source_key),
            )
            self.decisions.execute(
                """
                INSERT INTO transcription_decision_history(
                    source_kind, source_key, action, previous_json,
                    current_json, occurred_at_utc
                ) VALUES (?, ?, 'clear', ?, NULL, ?)
                """,
                (
                    item.source_kind,
                    item.source_key,
                    json.dumps(dict(previous), ensure_ascii=False),
                    now,
                ),
            )

    def stats(self, items: list[TranscriptionReviewItem] | None = None) -> dict[str, int]:
        current = items if items is not None else self.load_items()
        result = {
            "pending": 0,
            "machine_verified": 0,
            "confirmed": 0,
            "corrected": 0,
            "unresolved": 0,
            "stale": 0,
        }
        for item in current:
            state = item.review_state
            result[state] += 1
            if state == "stale":
                result["pending"] += 1
        return result


__all__ = [
    "TranscriptionReviewItem",
    "TranscriptionReviewStore",
    "VALID_TRANSCRIPTION_DECISIONS",
]
