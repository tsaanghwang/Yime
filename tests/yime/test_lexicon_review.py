from __future__ import annotations

import csv
import json
import sqlite3

from yime.utils.lexicon_review import export_review_queue, review_tier


def _create_runtime_database(path) -> None:
    with sqlite3.connect(path) as conn:
        conn.executescript(
            """
            CREATE TABLE runtime_candidates_materialized (
                entry_type TEXT NOT NULL,
                entry_id TEXT NOT NULL,
                text TEXT NOT NULL,
                pinyin_tone TEXT NOT NULL,
                yime_code TEXT NOT NULL,
                sort_weight REAL NOT NULL,
                is_common INTEGER NOT NULL,
                text_length INTEGER NOT NULL,
                updated_at TEXT NOT NULL
            );
            INSERT INTO runtime_candidates_materialized VALUES
                ('phrase', '1', '高优吧', 'gao1 you1 ba5', 'a', 100.0, 1, 3, 'now'),
                ('phrase', '2', '低频呢', 'di1 pin2 ne5', 'b', 20.0, 0, 3, 'now'),
                ('phrase', '3', '目的', 'mu4 di4', 'c', 500.0, 1, 2, 'now'),
                ('phrase', '4', '好的', 'hao3 de5', 'd', 400.0, 1, 2, 'now'),
                ('phrase', '5', '已批吗', 'yi3 pi1 ma5', 'e', 80.0, 1, 3, 'now'),
                ('phrase', '6', '待审吗', 'dai4 shen3 ma5', 'f', 60.0, 1, 3, 'now');
            """
        )


def _create_input_model_database(path) -> None:
    with sqlite3.connect(path) as conn:
        conn.executescript(
            """
            CREATE TABLE candidate_universe (
                text TEXT PRIMARY KEY,
                bcc_frequency INTEGER NOT NULL,
                baseline_class TEXT NOT NULL,
                baseline_policy TEXT NOT NULL,
                baseline_rule TEXT NOT NULL
            );
            CREATE TABLE assessments (
                text TEXT PRIMARY KEY,
                candidate_class TEXT NOT NULL,
                integration_policy TEXT NOT NULL,
                decision_status TEXT NOT NULL,
                rationale TEXT NOT NULL,
                assessor TEXT NOT NULL
            );
            CREATE TABLE context_evidence (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL
            );
            INSERT INTO candidate_universe VALUES
                ('高优吧', 10000, 'lexical_candidate', 'needs_review', 'gated'),
                ('低频呢', 9, 'place_name', 'static_keep', 'source_category'),
                ('目的', 999999, 'lexical_candidate', 'needs_review', 'gated'),
                ('好的', 999999, 'lexical_candidate', 'needs_review', 'gated'),
                ('已批吗', 5000, 'lexical_candidate', 'needs_review', 'gated'),
                ('待审吗', 1000, 'lexical_candidate', 'needs_review', 'gated');
            INSERT INTO assessments VALUES
                ('已批吗', 'fixed_expression', 'static_keep', 'approved', 'approved', 'human'),
                ('待审吗', 'context_dependent', 'needs_review', 'deferred', 'need context', 'human');
            INSERT INTO context_evidence VALUES (1, '待审吗');
            """
        )


def test_review_tiers_match_candidate_corpus_roadmap() -> None:
    assert review_tier(10000) == "bcc_ge_10000"
    assert review_tier(9999) == "bcc_1000_9999"
    assert review_tier(999) == "bcc_100_999"
    assert review_tier(99) == "bcc_10_99"
    assert review_tier(9) == "bcc_1_9"
    assert review_tier(0) == "no_bcc"


def test_export_review_queue_joins_overlay_without_writing_decisions(tmp_path) -> None:
    runtime_database = tmp_path / "runtime.db"
    input_model_database = tmp_path / "input_model.db"
    output_directory = tmp_path / "review"
    _create_runtime_database(runtime_database)
    _create_input_model_database(input_model_database)

    result = export_review_queue(
        runtime_database=runtime_database,
        input_model_database=input_model_database,
        output_directory=output_directory,
        summary_limit=10,
        per_suffix_limit=2,
    )

    assert result.queue_count == 3
    assert result.excluded_decided_count == 1
    with result.queue_path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert [row["text"] for row in rows] == ["高优吧", "待审吗", "低频呢"]
    assert rows[1]["decision_status"] == "deferred"
    assert rows[1]["has_context_evidence"] == "1"
    assert rows[1]["suggested_role"] == "modal_component_candidate"
    assert rows[1]["construction_systems"] == "modal_particles"
    assert rows[1]["construction_ids"] == "interrogative_ma"
    assert rows[2]["policy_lane"] == "source_classified"
    assert "目的" not in {row["text"] for row in rows}
    assert "好的" not in {row["text"] for row in rows}

    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))
    assert manifest["policy"]["writes_assessments"] is False
    assert manifest["counts"]["queue"] == 3
    assert manifest["counts"]["suggested_roles"] == {
        "modal_component_candidate": 3
    }
    assert manifest["counts"]["construction_systems"] == {
        "modal_particles": 3
    }
    assert "助词构式部件审阅摘要" in result.summary_path.read_text(
        encoding="utf-8"
    )

    with sqlite3.connect(input_model_database) as conn:
        assert conn.execute("SELECT COUNT(*) FROM assessments").fetchone()[0] == 2
