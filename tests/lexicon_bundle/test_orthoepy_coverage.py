from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

from yime.lexicon_bundle.orthoepy_coverage import (
    CoverageReviewStore,
    export_approved_catalog,
    restore_missing_syllable_spaces,
    run_coverage_audit,
)
from yime.lexicon_bundle.parsers import iter_reviewed_orthoepy_readings


ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "yime" / "pinyin_normalized.json"


def test_missing_spaces_restore_syllables_without_guessing_word_boundaries() -> None:
    assert restore_missing_syllable_spaces("dàiwáng", 2, INVENTORY) == "dài wáng"
    assert (
        restore_missing_syllable_spaces("gāngtiě dàwáng", 4, INVENTORY)
        == "gāng tiě dà wáng"
    )
    assert (
        restore_missing_syllable_spaces("bǎ dòng sāizhù", 4, INVENTORY)
        == "bǎ dòng sāi zhù"
    )
    assert restore_missing_syllable_spaces("cuōr", 2, INVENTORY) is None
    assert restore_missing_syllable_spaces("pèijuér", 3, INVENTORY) is None
    assert restore_missing_syllable_spaces("juér", 2, INVENTORY) is None
    assert restore_missing_syllable_spaces("dàwáng", 5, INVENTORY) is None


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _create_psc(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.executescript(
            """
            CREATE TABLE orthoepy_datasets (
                id INTEGER PRIMARY KEY, dataset_key TEXT NOT NULL
            );
            CREATE TABLE orthoepy_source_rows (id INTEGER PRIMARY KEY);
            CREATE TABLE orthoepy_entries (
                id INTEGER PRIMARY KEY,
                dataset_id INTEGER NOT NULL,
                version_key TEXT NOT NULL,
                authority_status TEXT NOT NULL,
                source_row INTEGER NOT NULL,
                word_page_number INTEGER NOT NULL,
                section_label TEXT NOT NULL,
                entry_text TEXT NOT NULL,
                headword TEXT NOT NULL,
                inherited_from_1985 INTEGER NOT NULL
            );
            INSERT INTO orthoepy_datasets VALUES
                (1, 'putonghua-orthoepy-1985-with-2016-draft');
            INSERT INTO orthoepy_entries VALUES
                (1,1,'official_1985','official',10,2,'B',
                 '蚌（一）bàng\n蛤～\n（二）bèng\n～埠','蚌',0),
                (2,1,'draft_2016','consultation_draft',11,3,'B',
                 '拜bái（统读）','拜',0),
                (3,1,'draft_2016','consultation_draft',12,3,'B',
                 '蚌（一）bàng\n蛤～\n（二）bèng\n～埠','蚌',1),
                (4,1,'official_1985','official',13,3,'C',
                 '绰chuò\n～～有余','绰',0);
            """
        )
        connection.commit()
    finally:
        connection.close()


def _create_source(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.executescript(
            """
            CREATE TABLE canonical_readings (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL DEFAULT 'pypinyin'
            );
            INSERT INTO canonical_readings VALUES
                (1,'蚌','bèng','beng4',1,1,'pypinyin'),
                (2,'蛤','há','ha2',1,1,'pypinyin'),
                (3,'蚌埠','bèng bù','beng4 bu4',1,1,'pypinyin'),
                (4,'埠','bù','bu4',1,1,'pypinyin');
            INSERT INTO canonical_readings VALUES
                (5,'绰','chuò','chuo4',1,1,'pypinyin'),
                (6,'绰绰有余','chuò chuò yǒu yú','chuo4 chuo4 you3 yu2',1,1,'pypinyin');
            """
        )
        connection.commit()
    finally:
        connection.close()


def test_audit_builds_coverage_only_queue_and_preserves_inputs(tmp_path: Path) -> None:
    psc = tmp_path / "psc.sqlite3"
    source = tmp_path / "source.sqlite3"
    audit = tmp_path / "audit.sqlite3"
    _create_psc(psc)
    _create_source(source)
    before = (_hash(psc), _hash(source))

    result = run_coverage_audit(
        psc, source, audit, decoder_inventory=INVENTORY
    )

    assert before == (_hash(psc), _hash(source))
    assert result["automatic_official_additions"] == 1
    connection = sqlite3.connect(audit)
    connection.row_factory = sqlite3.Row
    try:
        automatic = connection.execute(
            "SELECT * FROM automatic_official_additions"
        ).fetchone()
        assert automatic["text"] == "蚌"
        assert automatic["proposed_numeric_pinyin"] == "bang4"
        phrase = connection.execute(
            "SELECT * FROM review_queue WHERE text='蛤蚌'"
        ).fetchone()
        assert phrase["proposed_marked_pinyin"] == "há bàng"
        assert phrase["coverage_status"] == "missing_text"
        covered = connection.execute(
            "SELECT coverage_status FROM candidates WHERE text='蚌埠'"
        ).fetchone()
        assert covered[0] == "covered_exact"
        repeated = connection.execute(
            "SELECT coverage_status FROM candidates WHERE text='绰绰有余'"
        ).fetchone()
        assert repeated[0] == "covered_exact"
        draft = connection.execute(
            "SELECT auto_eligible, requires_review FROM candidates WHERE text='拜'"
        ).fetchone()
        assert tuple(draft) == (0, 1)
    finally:
        connection.close()


def test_review_decisions_export_a_non_primary_source_catalog(tmp_path: Path) -> None:
    psc = tmp_path / "psc.sqlite3"
    source = tmp_path / "source.sqlite3"
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "decisions.sqlite3"
    catalog = tmp_path / "catalog.json"
    _create_psc(psc)
    _create_source(source)
    run_coverage_audit(psc, source, audit, decoder_inventory=INVENTORY)

    store = CoverageReviewStore(audit, decisions)
    try:
        phrase = next(item for item in store.load_items() if item.candidate.text == "蛤蚌")
        store.save(phrase.candidate.candidate_key, "approve", note="fixture")
        result = export_approved_catalog(store, catalog, decoder_inventory=INVENTORY)
    finally:
        store.close()

    assert result["record_count"] == 2
    records = list(iter_reviewed_orthoepy_readings(catalog))
    assert {(record.text, record.reading) for record in records} == {
        ("蚌", "bàng"),
        ("蛤蚌", "há bàng"),
    }
    assert all(not record.source_primary for record in records)
    payload = json.loads(catalog.read_text(encoding="utf-8"))
    assert not any(record["text"] == "拜" for record in payload["records"])


def test_export_is_stable_after_its_records_are_rebuilt_into_source(tmp_path: Path) -> None:
    psc = tmp_path / "psc.sqlite3"
    source = tmp_path / "source.sqlite3"
    first_audit = tmp_path / "first.sqlite3"
    second_audit = tmp_path / "second.sqlite3"
    decisions = tmp_path / "decisions.sqlite3"
    catalog = tmp_path / "catalog.json"
    _create_psc(psc)
    _create_source(source)
    run_coverage_audit(psc, source, first_audit, decoder_inventory=INVENTORY)

    store = CoverageReviewStore(first_audit, decisions)
    try:
        phrase = next(item for item in store.load_items() if item.candidate.text == "蛤蚌")
        store.save(phrase.candidate.candidate_key, "approve", note="fixture")
        first = export_approved_catalog(store, catalog, decoder_inventory=INVENTORY)
    finally:
        store.close()
    assert first["record_count"] == 2

    with sqlite3.connect(source) as connection:
        connection.executemany(
            "INSERT INTO canonical_readings VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
                (7, "蚌", "bàng", "bang4", 2, 0, "psc_orthoepy_1985"),
                (8, "蛤蚌", "há bàng", "ha2 bang4", 1, 1, "psc_orthoepy_1985"),
            ],
        )
        connection.commit()

    run_coverage_audit(psc, source, second_audit, decoder_inventory=INVENTORY)
    store = CoverageReviewStore(second_audit, decisions)
    try:
        second = export_approved_catalog(store, catalog, decoder_inventory=INVENTORY)
    finally:
        store.close()
    assert second["record_count"] == 2


def test_stale_decision_is_not_exported(tmp_path: Path) -> None:
    psc = tmp_path / "psc.sqlite3"
    source = tmp_path / "source.sqlite3"
    audit = tmp_path / "audit.sqlite3"
    decisions = tmp_path / "decisions.sqlite3"
    catalog = tmp_path / "catalog.json"
    _create_psc(psc)
    _create_source(source)
    run_coverage_audit(psc, source, audit, decoder_inventory=INVENTORY)
    store = CoverageReviewStore(audit, decisions)
    try:
        draft = next(item for item in store.load_items() if item.candidate.text == "拜")
        store.save(draft.candidate.candidate_key, "approve")
    finally:
        store.close()

    connection = sqlite3.connect(audit)
    try:
        connection.execute(
            "UPDATE candidates SET fingerprint='changed' WHERE text='拜'"
        )
        connection.commit()
    finally:
        connection.close()
    store = CoverageReviewStore(audit, decisions)
    try:
        export_approved_catalog(store, catalog, decoder_inventory=INVENTORY)
    finally:
        store.close()
    payload = json.loads(catalog.read_text(encoding="utf-8"))
    assert not any(record["text"] == "拜" for record in payload["records"])
