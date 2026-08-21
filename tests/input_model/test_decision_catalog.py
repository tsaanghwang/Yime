from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from yime.input_model.decision_catalog import (
    apply_decision_catalog,
    load_decision_catalog,
    plan_decision_catalog,
)
from yime.input_model.store import InputModelStore


def _create_input_model(path: Path) -> None:
    with InputModelStore(path) as store:
        store.connection.executemany(
            """
            INSERT INTO candidate_universe (
                text, text_length, bcc_frequency, has_bcc_evidence,
                has_gated_reading, has_source_rejection, baseline_class,
                baseline_policy, baseline_rule, baseline_status,
                dynamic_reachable, dynamic_reachability_rule,
                last_seen_generation
            ) VALUES (?, ?, ?, ?, ?, 0, 'unknown', 'needs_review',
                      'fixture', 'proposed', 0, '', 'fixture')
            """,
            (
                ("为了", 2, 100, 1, 1),
                ("片段的", 3, 0, 0, 1),
                ("未编码", 3, 0, 0, 0),
            ),
        )
        store.connection.commit()


def _write_catalog(path: Path, decisions: list[dict[str, object]]) -> Path:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "safeguards": {
                    "source_lexicon_is_read_only": True,
                    "frequency_orders_review_only": True,
                },
                "batches": [
                    {
                        "batch_id": "pilot",
                        "decisions": decisions,
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return path


def test_dry_run_is_read_only_and_apply_is_idempotent(tmp_path: Path) -> None:
    database = tmp_path / "input_model.sqlite3"
    _create_input_model(database)
    catalog = _write_catalog(
        tmp_path / "decisions.json",
        [
            {
                "text": "为了",
                "bcc_frequency_at_review": 99,
                "candidate_class": "fixed_expression",
                "integration_policy": "static_keep",
                "decision_status": "approved",
                "confidence": 0.99,
                "rationale": "固定表达。",
                "assessor": "test:reviewer",
            },
            {
                "text": "片段的",
                "bcc_frequency_at_review": 0,
                "candidate_class": "context_dependent",
                "integration_policy": "needs_review",
                "decision_status": "deferred",
                "rationale": "等待上下文。",
                "assessor": "test:reviewer",
            },
        ],
    )
    decisions = load_decision_catalog(catalog)

    plan = plan_decision_catalog(database, decisions)
    assert (plan.created, plan.updated, plan.unchanged) == (2, 0, 0)
    assert plan.frequency_drift == ("为了",)
    with sqlite3.connect(database) as connection:
        assert connection.execute("SELECT COUNT(*) FROM assessments").fetchone()[0] == 0

    applied = apply_decision_catalog(database, decisions)
    assert applied == plan
    second = apply_decision_catalog(database, decisions)
    assert (second.created, second.updated, second.unchanged) == (0, 0, 2)
    with sqlite3.connect(database) as connection:
        rows = connection.execute(
            "SELECT text, decision_status FROM assessments ORDER BY text"
        ).fetchall()
    assert rows == [("为了", "approved"), ("片段的", "deferred")]


def test_catalog_reject_requires_noise_and_reject_policy(tmp_path: Path) -> None:
    catalog = _write_catalog(
        tmp_path / "decisions.json",
        [
            {
                "text": "误切片段",
                "candidate_class": "syntactic_fragment",
                "integration_policy": "reject",
                "decision_status": "rejected",
                "rationale": "测试。",
                "assessor": "test:reviewer",
            }
        ],
    )
    with pytest.raises(ValueError, match="noise \\+ reject"):
        load_decision_catalog(catalog)


def test_approved_catalog_decision_requires_gated_reading(tmp_path: Path) -> None:
    database = tmp_path / "input_model.sqlite3"
    _create_input_model(database)
    catalog = _write_catalog(
        tmp_path / "decisions.json",
        [
            {
                "text": "未编码",
                "candidate_class": "lexical_candidate",
                "integration_policy": "static_keep",
                "decision_status": "approved",
                "rationale": "测试。",
                "assessor": "test:reviewer",
            }
        ],
    )
    with pytest.raises(ValueError, match="no gated source reading"):
        plan_decision_catalog(database, load_decision_catalog(catalog))


def test_apply_refuses_to_replace_conflicting_assessment_by_default(
    tmp_path: Path,
) -> None:
    database = tmp_path / "input_model.sqlite3"
    _create_input_model(database)
    first_catalog = _write_catalog(
        tmp_path / "first.json",
        [
            {
                "text": "为了",
                "candidate_class": "fixed_expression",
                "integration_policy": "static_keep",
                "decision_status": "approved",
                "rationale": "第一版。",
                "assessor": "test:reviewer",
            }
        ],
    )
    first = load_decision_catalog(first_catalog)
    apply_decision_catalog(database, first)

    second_catalog = _write_catalog(
        tmp_path / "second.json",
        [
            {
                "text": "为了",
                "candidate_class": "fixed_expression",
                "integration_policy": "static_keep",
                "decision_status": "approved",
                "rationale": "第二版。",
                "assessor": "test:reviewer",
            }
        ],
    )
    second = load_decision_catalog(second_catalog)
    with pytest.raises(ValueError, match="refusing to overwrite"):
        apply_decision_catalog(database, second)
    applied = apply_decision_catalog(database, second, overwrite=True)
    assert applied.updated == 1
