from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

import pytest

from yime.lexicon_bundle.psc_transcription_review import (
    TranscriptionReviewStore,
    next_visible_key_after_save,
)


@pytest.mark.parametrize(
    ("previous", "current", "refreshed", "expected"),
    (
        (("a", "b", "c"), "b", ("a", "b", "c"), "c"),
        (("a", "b", "c"), "b", ("a", "c"), "c"),
        (("a", "b", "c"), "c", ("a", "b", "c"), "a"),
        (("a", "b", "c"), "c", ("a", "b"), "a"),
        (("a",), "a", ("a",), "a"),
        (("a",), "a", (), None),
    ),
)
def test_next_visible_key_after_save(
    previous: tuple[str, ...],
    current: str,
    refreshed: tuple[str, ...],
    expected: str | None,
) -> None:
    assert next_visible_key_after_save(previous, current, refreshed) == expected


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _create_audit_database(path: Path, *, changed: bool = False) -> None:
    source_snapshot = {"path": str(path.parent / "source.sqlite3"), "sha256": "source"}
    psc_snapshot = {"path": str(path.parent / "psc.sqlite3"), "sha256": "psc"}
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE audit_run (
                id INTEGER PRIMARY KEY, source_db_json TEXT NOT NULL,
                psc_db_json TEXT NOT NULL
            );
            CREATE TABLE audit_detail (
                id INTEGER PRIMARY KEY, source_kind TEXT NOT NULL,
                source_key TEXT NOT NULL, source_order INTEGER NOT NULL,
                text TEXT NOT NULL, pinyin_raw TEXT NOT NULL,
                locator_json TEXT NOT NULL, review_lane TEXT NOT NULL,
                review_priority INTEGER NOT NULL,
                canonical_readings_json TEXT NOT NULL,
                accepted_readings_json TEXT NOT NULL,
                explanation TEXT NOT NULL
            );
            """
        )
        connection.execute(
            "INSERT INTO audit_run VALUES (1, ?, ?)",
            (json.dumps(source_snapshot), json.dumps(psc_snapshot)),
        )
        connection.executemany(
            "INSERT INTO audit_detail VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                (
                    1,
                    "psc_main",
                    "1:1",
                    1,
                    "阿姨" if not changed else "阿一",
                    "āyí",
                    json.dumps({"page_number": 1, "column_number": 1}),
                    "canonical_pronunciation_review",
                    100,
                    json.dumps([{"marked": "ā yí", "numeric": "a1 yi2"}]),
                    "[]",
                    "comparison only",
                ),
                (
                    2,
                    "psc_neutral_tone",
                    "1",
                    1,
                    "规矩",
                    "guījǔ",
                    json.dumps({"page_number": 1}),
                    "verified",
                    0,
                    "[]",
                    "[]",
                    "matched",
                ),
            ),
        )


def test_transcription_review_is_separate_and_read_only_toward_audit(tmp_path: Path) -> None:
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "transcription.sqlite3"
    _create_audit_database(audit)
    before = _digest(audit)

    store = TranscriptionReviewStore(audit, decisions)
    try:
        items = store.load_items()
        assert len(items) == 2
        item = items[0]
        assert item.needs_reference_check
        with pytest.raises(ValueError, match="must equal"):
            store.save(item, "confirmed", "阿一", "āyí")
        with pytest.raises(ValueError, match="must change"):
            store.save(item, "corrected", item.text, item.pinyin)
        with pytest.raises(ValueError, match="unsupported"):
            store.save(item, "keep_source", item.text, item.pinyin)

        store.save(item, "confirmed", item.text, item.pinyin, "与来源一致")
        restored = store.load_items()[0]
        assert restored.decision == "confirmed"
        assert restored.note == "与来源一致"
        assert restored.effective_text == restored.text
        assert restored.effective_pinyin == restored.pinyin
        assert store.load_items()[1].review_state == "machine_verified"
        assert store.stats(store.load_items()) == {
            "pending": 0,
            "machine_verified": 1,
            "confirmed": 1,
            "corrected": 0,
            "unresolved": 0,
            "stale": 0,
        }
        assert store.decisions.execute(
            "SELECT COUNT(*) FROM transcription_decision_history"
        ).fetchone()[0] == 1
    finally:
        store.close()

    assert _digest(audit) == before
    assert decisions.is_file()


def test_decisions_survive_audit_rebuild_and_changed_records_require_recheck(
    tmp_path: Path,
) -> None:
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "transcription.sqlite3"
    _create_audit_database(audit)
    store = TranscriptionReviewStore(audit, decisions)
    try:
        item = store.load_items()[0]
        store.save(item, "corrected", "阿姨", "ā yí", "补回音节分隔")
    finally:
        store.close()

    rebuilt_audit = tmp_path / "rebuilt-audit.sqlite3"
    _create_audit_database(rebuilt_audit, changed=True)
    rebuilt = TranscriptionReviewStore(rebuilt_audit, decisions)
    try:
        item = rebuilt.load_items()[0]
        assert item.stale_decision
        assert item.decision == "pending"
        assert item.corrected_pinyin == "ā yí"
        assert item.effective_text == "阿一"
        assert item.effective_pinyin == "āyí"
        rebuilt.save(item, "unresolved", item.text, item.pinyin, "来源记录变化后重查")
        refreshed = rebuilt.load_items()[0]
        assert not refreshed.stale_decision
        assert refreshed.decision == "unresolved"
        assert rebuilt.decisions.execute(
            "SELECT COUNT(*) FROM transcription_decision_history"
        ).fetchone()[0] == 2
    finally:
        rebuilt.close()


def test_clear_appends_history_without_touching_audit(tmp_path: Path) -> None:
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "transcription.sqlite3"
    _create_audit_database(audit)
    before = _digest(audit)
    store = TranscriptionReviewStore(audit, decisions)
    try:
        item = store.load_items()[0]
        store.save(item, "unresolved", item.text, item.pinyin, "待查")
        store.clear(item)
        assert store.load_items()[0].decision == "pending"
        assert store.decisions.execute(
            "SELECT COUNT(*) FROM transcription_decision_history"
        ).fetchone()[0] == 2
    finally:
        store.close()
    assert _digest(audit) == before


def test_corrected_values_are_the_effective_transcription(tmp_path: Path) -> None:
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "transcription.sqlite3"
    _create_audit_database(audit)
    store = TranscriptionReviewStore(audit, decisions)
    try:
        item = store.load_items()[0]
        store.save(item, "corrected", "阿姨", "ā yí", "补回分隔")
        corrected = store.load_items()[0]
        assert corrected.text == "阿姨"
        assert corrected.pinyin == "āyí"
        assert corrected.effective_text == "阿姨"
        assert corrected.effective_pinyin == "ā yí"
    finally:
        store.close()
