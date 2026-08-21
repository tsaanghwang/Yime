from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

import pytest

from yime.lexicon_bundle.psc_audit import (
    Observation,
    Reading,
    ReviewDecisionStore,
    classify_observation,
    normalize_marked_pinyin,
    run_audit,
    split_marked_variants,
)


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _reading(
    marked: str,
    *,
    primary: bool = True,
    source: str = "fixture",
) -> Reading:
    return Reading(
        marked=marked,
        numeric="fixture",
        normalized=normalize_marked_pinyin(marked),
        is_primary=primary,
        reading_rank=1 if primary else 2,
        sources=source,
        neutral_tone_status="none",
    )


def _observation(source_kind: str, text: str, pinyin: str) -> Observation:
    return Observation(source_kind, "1", 1, text, pinyin, {"fixture": True})


def _create_source_database(path: Path) -> None:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE canonical_readings (
                text TEXT NOT NULL, marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL, reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL, pinyin_sources TEXT NOT NULL,
                neutral_tone_status TEXT NOT NULL
            );
            CREATE INDEX canonical_text_idx ON canonical_readings(text);
            CREATE TABLE accepted_readings (
                text TEXT NOT NULL, marked TEXT NOT NULL, numeric TEXT NOT NULL,
                source_rank INTEGER NOT NULL, source_primary INTEGER NOT NULL,
                source TEXT NOT NULL, neutral_tone_status TEXT NOT NULL
            );
            CREATE INDEX accepted_text_idx ON accepted_readings(text);
            INSERT INTO canonical_readings VALUES
                ('事实', 'shì shí', 'shi4 shi2', 1, 1, 'fixture', 'none'),
                ('为', 'wèi', 'wei4', 1, 1, 'fixture', 'none'),
                ('为', 'wéi', 'wei2', 2, 0, 'fixture', 'none'),
                ('规矩', 'guī ju', 'gui1 ju5', 1, 1, 'fixture', 'attested_neutral'),
                ('花儿', 'huā ér', 'hua1 er2', 1, 1, 'fixture', 'none'),
                ('捌', 'bā', 'ba1', 1, 1, 'fixture', 'none');
            INSERT INTO accepted_readings VALUES
                ('来源词', 'lái yuán cí', 'lai2 yuan2 ci2', 2, 0, 'fixture', 'none');
            """
        )


def _create_psc_database(path: Path) -> None:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE main_rows (
                table_number INTEGER, source_index INTEGER, reviewed_hanzi TEXT,
                reviewed_pinyin TEXT, page_number INTEGER, column_number INTEGER,
                review_decision TEXT
            );
            CREATE VIEW manually_reviewed_entries AS SELECT * FROM main_rows;
            INSERT INTO main_rows VALUES
                (1, 1, '事实', 'shìshí', 1, 1, 'pending'),
                (1, 2, '为', 'wéi', 1, 1, 'pending'),
                (1, 3, '来源词', 'láiyuáncí', 1, 1, 'pending'),
                (1, 4, '缺词', 'quēcí', 1, 1, 'pending');
            CREATE TABLE neutral_tone_entries (
                id INTEGER, source_index INTEGER, hanzi TEXT, pinyin_nfc TEXT,
                page_number INTEGER, table_order INTEGER, row_order INTEGER,
                pair_order INTEGER
            );
            INSERT INTO neutral_tone_entries VALUES (1, 1, '规矩', 'guīju', 1, 1, 1, 1);
            CREATE TABLE erhua_categories (
                id INTEGER, source_index INTEGER, rule_nfc TEXT
            );
            INSERT INTO erhua_categories VALUES (1, 1, 'a→ar');
            CREATE TABLE erhua_entries (
                id INTEGER, source_index INTEGER, hanzi TEXT, pinyin_nfc TEXT,
                page_number INTEGER, table_order INTEGER, row_order INTEGER,
                pair_order INTEGER, category_id INTEGER
            );
            INSERT INTO erhua_entries VALUES (1, 1, '花儿', 'huār', 1, 1, 1, 1, 1);
            CREATE TABLE rare_word_groups (id INTEGER, group_label TEXT);
            INSERT INTO rare_word_groups VALUES (1, 'fixture');
            CREATE TABLE rare_word_entries (
                id INTEGER, source_index INTEGER, hanzi TEXT, pinyin_nfc TEXT,
                sheet_name TEXT, source_row INTEGER, pair_order INTEGER,
                group_id INTEGER
            );
            INSERT INTO rare_word_entries VALUES (1, 1, '捌', 'bā', 'fixture', 1, 1, 1);
            CREATE TABLE passage_pronunciation_passages (
                id INTEGER, work_no INTEGER, title TEXT, pdf_page_number INTEGER
            );
            INSERT INTO passage_pronunciation_passages VALUES (1, 1, 'fixture', 1);
            CREATE TABLE passage_pronunciation_entries (
                id INTEGER, source_index INTEGER, term TEXT, pinyin_nfc TEXT,
                entry_order INTEGER, source_item_no INTEGER,
                source_item_occurrence INTEGER, review_status TEXT,
                passage_id INTEGER
            );
            INSERT INTO passage_pronunciation_entries VALUES
                (1, 1, '为', 'wèi', 1, 1, 1, 'accepted', 1);
            """
        )


def test_marked_comparison_ignores_layout_but_keeps_tone() -> None:
    assert normalize_marked_pinyin("líng qī-bā suìr") == "língqībāsuìr"
    assert split_marked_variants("ā/ē／ā") == ("ā", "ē")
    assert normalize_marked_pinyin("wéi") != normalize_marked_pinyin("wèi")
    assert split_marked_variants("（ ）") == ()


def test_classification_keeps_special_evidence_out_of_auto_promotion() -> None:
    primary = (_reading("huā ér"),)
    erhua = classify_observation(_observation("psc_erhua", "花儿", "huār"), primary, ())
    assert erhua.outcome == "erhua_policy_review"
    assert erhua.review_lane == "erhua_policy_review"

    neutral = classify_observation(
        _observation("psc_neutral_tone", "规矩", "guīju"),
        (_reading("guī jǔ"),),
        (),
    )
    assert neutral.outcome == "pronunciation_conflict"
    assert neutral.review_lane == "neutral_tone_review"

    duplicated_neutral = classify_observation(
        _observation("psc_main", "规矩", "guīju"),
        (_reading("guī jǔ"),),
        (),
        known_neutral_evidence=True,
    )
    assert duplicated_neutral.review_lane == "neutral_tone_review"

    duplicated_erhua = classify_observation(
        _observation("psc_main", "花儿", "huār"),
        (_reading("huā ér"),),
        (),
        known_erhua_evidence=True,
    )
    assert duplicated_erhua.review_lane == "erhua_policy_review"

    lexical_er = classify_observation(
        _observation("psc_main", "女儿", "nǚér"),
        (_reading("nǚ ér"),),
        (),
    )
    assert lexical_er.review_lane == "verified"

    implicit_erhua = classify_observation(
        _observation("psc_passage", "蒜瓣", "suànbànr"),
        (_reading("suàn bàn"),),
        (),
    )
    assert implicit_erhua.review_lane == "erhua_policy_review"


def test_main_classification_distinguishes_primary_alternate_and_source_only() -> None:
    primary = classify_observation(
        _observation("psc_main", "为", "wèi"),
        (_reading("wèi"), _reading("wéi", primary=False)),
        (),
    )
    alternate = classify_observation(
        _observation("psc_main", "为", "wéi"),
        (_reading("wèi"), _reading("wéi", primary=False)),
        (),
    )
    source_only = classify_observation(
        _observation("psc_main", "来源词", "láiyuáncí"),
        (),
        (_reading("lái yuán cí", primary=False),),
    )
    assert primary.review_lane == "verified"
    assert alternate.review_lane == "primary_ranking_review"
    assert source_only.review_lane == "canonical_promotion_review"


def test_supplemental_and_contextual_alternates_do_not_request_primary_promotion() -> None:
    readings = (_reading("wèi"), _reading("wéi", primary=False))
    rare = classify_observation(_observation("psc_rare_word", "为", "wéi"), readings, ())
    passage = classify_observation(_observation("psc_passage", "为", "wéi"), readings, ())
    assert rare.review_lane == "supplemental_reference_review"
    assert passage.review_lane == "contextual_reference_review"


def test_full_audit_is_complete_and_does_not_modify_inputs(tmp_path: Path) -> None:
    source_db = tmp_path / "source.sqlite3"
    psc_db = tmp_path / "psc.sqlite3"
    _create_source_database(source_db)
    _create_psc_database(psc_db)
    before = (_digest(source_db), _digest(psc_db))

    artifacts = run_audit(source_db, psc_db, tmp_path / "audit")

    assert before == (_digest(source_db), _digest(psc_db))
    assert artifacts.observation_count == 8
    with sqlite3.connect(artifacts.database) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert connection.execute("SELECT COUNT(*) FROM observations").fetchone()[0] == 8
        assert connection.execute("SELECT COUNT(*) FROM audit_results").fetchone()[0] == 8
        assert connection.execute("SELECT COUNT(*) FROM audit_detail").fetchone()[0] == 8
        assert connection.execute(
            "SELECT COUNT(*) FROM consolidated_review_queue"
        ).fetchone()[0] == artifacts.review_case_count
        assert connection.execute(
            "SELECT COUNT(*) FROM review_evidence_queue"
        ).fetchone()[0] == artifacts.review_observation_count
        assert connection.execute("SELECT COUNT(*) FROM review_queue").fetchone()[0] == (
            artifacts.pending_case_count
        )
        assert connection.execute(
            "SELECT COUNT(*) FROM audit_results WHERE review_lane='erhua_policy_review'"
        ).fetchone()[0] == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM audit_results WHERE review_lane='canonical_promotion_review'"
        ).fetchone()[0] == 1
    summary = json.loads(artifacts.summary_json.read_text(encoding="utf-8"))
    assert summary["counts"]["observations"] == 8
    assert sum(summary["counts"]["by_source"].values()) == 8
    assert summary["safeguards"]["automatic_corrections_applied"] == 0
    assert "自动改写真源：**0**" in artifacts.report_markdown.read_text(encoding="utf-8")
    assert len(artifacts.review_tsv.read_text(encoding="utf-8").splitlines()) == (
        artifacts.review_case_count + 1
    )


def test_review_decisions_keep_history_and_survive_audit_rebuild(tmp_path: Path) -> None:
    source_db = tmp_path / "source.sqlite3"
    psc_db = tmp_path / "psc.sqlite3"
    output_dir = tmp_path / "audit"
    _create_source_database(source_db)
    _create_psc_database(psc_db)
    before = (_digest(source_db), _digest(psc_db))
    first = run_audit(source_db, psc_db, output_dir)

    store = ReviewDecisionStore(first.database)
    try:
        case = store.load_cases()[0]
        with pytest.raises(ValueError, match="selected_pinyin"):
            store.save_decision(case.case_key, "accept_psc")
        with pytest.raises(ValueError, match="note"):
            store.save_decision(case.case_key, "psc_evidence_error")
        with pytest.raises(ValueError, match="unsupported"):
            store.save_decision(case.case_key, "invented")
        store.save_decision(case.case_key, "keep_source", note="fixture decision")
        store.save_decision(case.case_key, "defer", note="needs dictionary evidence")
        assert store.stats()["defer"] == 1
        assert store.connection.execute(
            "SELECT COUNT(*) FROM review_decision_history WHERE case_key=?",
            (case.case_key,),
        ).fetchone()[0] == 2
    finally:
        store.close()

    second = run_audit(source_db, psc_db, output_dir)
    assert before == (_digest(source_db), _digest(psc_db))
    assert second.decided_case_count == 1
    assert second.pending_case_count == second.review_case_count - 1
    rebuilt = ReviewDecisionStore(second.database)
    try:
        restored = next(item for item in rebuilt.load_cases() if item.case_key == case.case_key)
        assert restored.decision == "defer"
        assert restored.note == "needs dictionary evidence"
        assert rebuilt.connection.execute(
            "SELECT COUNT(*) FROM review_decision_history WHERE case_key=?",
            (case.case_key,),
        ).fetchone()[0] == 2
        assert rebuilt.connection.execute(
            "SELECT COUNT(*) FROM orphaned_review_decisions"
        ).fetchone()[0] == 0
        rebuilt.clear_decision(case.case_key)
        assert rebuilt.stats()["pending"] == second.review_case_count
        assert rebuilt.connection.execute(
            "SELECT COUNT(*) FROM review_decision_history WHERE case_key=?",
            (case.case_key,),
        ).fetchone()[0] == 3
    finally:
        rebuilt.close()


def test_batch_decisions_are_atomic_and_keep_per_case_history(tmp_path: Path) -> None:
    source_db = tmp_path / "source.sqlite3"
    psc_db = tmp_path / "psc.sqlite3"
    _create_source_database(source_db)
    _create_psc_database(psc_db)
    artifacts = run_audit(source_db, psc_db, tmp_path / "audit")
    store = ReviewDecisionStore(artifacts.database)
    try:
        cases = store.load_cases()
        assert len(cases) >= 2
        with pytest.raises(KeyError, match="not active"):
            store.save_decisions_batch(
                (
                    {
                        "case_key": cases[0].case_key,
                        "decision": "defer",
                        "note": "valid but must roll back",
                    },
                    {
                        "case_key": "missing-case",
                        "decision": "defer",
                        "note": "invalid key",
                    },
                )
            )
        assert store.stats()["pending"] == len(cases)

        saved = store.save_decisions_batch(
            tuple(
                {
                    "case_key": case.case_key,
                    "decision": "defer",
                    "note": "batch fixture",
                }
                for case in cases[:2]
            ),
            reviewer="batch-rule:fixture",
        )
        assert saved == 2
        assert store.stats()["defer"] == 2
        assert store.connection.execute(
            "SELECT COUNT(*) FROM review_decision_history WHERE action='save'"
        ).fetchone()[0] == 2
        assert store.connection.execute(
            "SELECT COUNT(*) FROM review_decisions WHERE reviewer='batch-rule:fixture'"
        ).fetchone()[0] == 2
    finally:
        store.close()
