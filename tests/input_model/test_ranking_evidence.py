from __future__ import annotations

import sqlite3
from pathlib import Path

from yime.input_model.ranking_evidence import (
    AWAITING_CORPUS,
    DIRECT_BCC,
    PROVISIONAL_LMDG,
    PROVISIONAL_STRUCTURAL,
    audit_runtime_ranking_evidence,
    build_ranking_calibration,
    resolve_ranking_evidence,
)


def _source(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE canonical_readings (
                text TEXT NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                wanxiang_weight INTEGER NOT NULL
            );
            INSERT INTO canonical_readings VALUES
                ('甲词', 6, 999999),
                ('乙词', 0, 10),
                ('丙词', 0, 100),
                ('丁词', 0, 1000),
                ('无据', 0, 0),
                ('五字候选项', 0, 10);
            """
        )
    return path


def _capacity(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE static_capacity_items (
                text TEXT PRIMARY KEY,
                utility_score REAL NOT NULL
            );
            INSERT INTO static_capacity_items VALUES
                ('无据', 0.25),
                ('另无据', 0.75);
            """
        )
    return path


def test_bcc_is_primary_and_lmdg_is_strictly_bounded_fallback(
    tmp_path: Path,
) -> None:
    calibration = build_ranking_calibration(
        source_database=_source(tmp_path / "source.sqlite3")
    )
    direct = resolve_ranking_evidence(
        {
            "text": "甲词",
            "text_length": 2,
            "bcc_frequency": 6,
            "wanxiang_weight": 999999,
            "is_primary": 1,
        },
        calibration,
    )
    low = resolve_ranking_evidence(
        {
            "text": "乙词",
            "text_length": 2,
            "bcc_frequency": 0,
            "wanxiang_weight": 10,
            "is_primary": 1,
        },
        calibration,
    )
    high = resolve_ranking_evidence(
        {
            "text": "丁词",
            "text_length": 2,
            "bcc_frequency": 0,
            "wanxiang_weight": 1000,
            "is_primary": 1,
        },
        calibration,
    )
    assert direct.evidence_source == DIRECT_BCC
    assert direct.bcc_frequency == 6
    assert direct.wanxiang_weight == 999999
    assert not direct.provisional
    assert low.evidence_source == high.evidence_source == PROVISIONAL_LMDG
    assert low.effective_weight < high.effective_weight
    assert high.effective_weight < direct.effective_weight
    assert low.requires_independent_corpus


def test_missing_lmdg_keeps_buildable_awaiting_corpus_state(
    tmp_path: Path,
) -> None:
    calibration = build_ranking_calibration(
        source_database=_source(tmp_path / "source.sqlite3")
    )
    evidence = resolve_ranking_evidence(
        {
            "text": "无据",
            "text_length": 2,
            "bcc_frequency": 0,
            "wanxiang_weight": 0,
            "is_primary": 1,
        },
        calibration,
    )
    assert evidence.evidence_source == AWAITING_CORPUS
    assert evidence.effective_weight == 0
    assert evidence.requires_independent_corpus
    assert not evidence.provisional


def test_structural_floor_breaks_no_corpus_ties_without_claiming_frequency(
    tmp_path: Path,
) -> None:
    source = _source(tmp_path / "source.sqlite3")
    capacity = _capacity(tmp_path / "capacity.sqlite3")
    calibration = build_ranking_calibration(
        source_database=source,
        capacity_database=capacity,
    )
    evidence = resolve_ranking_evidence(
        {
            "text": "无据",
            "text_length": 2,
            "bcc_frequency": 0,
            "wanxiang_weight": 0,
            "utility_score": 0.25,
        },
        calibration,
    )
    assert evidence.evidence_source == PROVISIONAL_STRUCTURAL
    assert evidence.evidence_status == "provisional_non_frequency_tiebreak"
    assert 0 < evidence.effective_weight < calibration.fallback_minimum
    assert evidence.normalized_structural_percentile == 1.0
    assert evidence.bcc_frequency == evidence.wanxiang_weight == 0
    assert evidence.provisional
    assert evidence.requires_independent_corpus


def test_lmdg_percentiles_are_calibrated_within_length_bucket(
    tmp_path: Path,
) -> None:
    calibration = build_ranking_calibration(
        source_database=_source(tmp_path / "source.sqlite3")
    )
    two_character = resolve_ranking_evidence(
        {
            "text": "乙词",
            "text_length": 2,
            "bcc_frequency": 0,
            "wanxiang_weight": 10,
            "is_primary": 0,
        },
        calibration,
    )
    five_plus = resolve_ranking_evidence(
        {
            "text": "五字候选项",
            "text_length": 5,
            "bcc_frequency": 0,
            "wanxiang_weight": 10,
            "is_primary": 0,
        },
        calibration,
    )
    assert two_character.normalized_fallback_percentile == 1 / 3
    assert five_plus.normalized_fallback_percentile == 1.0


def test_runtime_audit_classifies_every_selected_text(
    tmp_path: Path,
) -> None:
    source = _source(tmp_path / "source.sqlite3")
    selection = tmp_path / "selection.tsv"
    selection.write_text(
        "text\tbcc_frequency\twanxiang_weight\t"
        "ranking_evidence_source\tranking_evidence_status\t"
        "normalized_fallback_percentile\t"
        "normalized_structural_percentile\t"
        "ranking_evidence_provisional\t"
        "requires_independent_corpus\tselection_level\n"
        "甲词\t6\t999999\tdirect_bcc\tverified_corpus\t"
        "0\t0\t0\t0\tfirst_level\n"
        "乙词\t0\t10\tprovisional_rime_lmdg\t"
        "provisional_external_ranking\t0.333\t0\t1\t1\tfirst_level\n"
        "无据\t0\t0\tawaiting_corpus\t"
        "no_quantified_ranking_evidence\t0\t0\t0\t1\tsecond_level\n",
        encoding="utf-8",
    )
    audit = audit_runtime_ranking_evidence(
        source_database=source,
        selection_path=selection,
    )
    assert audit.selected_texts == audit.classified_selected_texts == 3
    assert audit.selected_counts == {
        "first_level": {
            DIRECT_BCC: 1,
            PROVISIONAL_LMDG: 1,
        },
        "second_level": {AWAITING_CORPUS: 1},
    }
    assert audit.source_priority_separation_passed
    assert audit.completion_passed
