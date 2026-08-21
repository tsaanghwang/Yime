from __future__ import annotations

import sqlite3

from yime.utils.lexicon_quality import (
    iter_review_samples,
    finalize_report,
    lint_runtime_db_file,
    lint_runtime_json_payload,
    lint_source_db_file,
    make_report,
    ends_with_particle,
    is_placeholder_phrase,
    is_whitelisted_phrase,
    particle_suffix_review_role,
)


def test_suffix_particle_detects_non_whitelisted_phrase() -> None:
    assert ends_with_particle("走了吗")
    assert ends_with_particle("走了吗", pinyin_tone="zou3 le5 ma5")
    assert not is_whitelisted_phrase("走了吗")


def test_suffix_particle_requires_particle_reading_when_pinyin_is_available() -> None:
    assert ends_with_particle("有的", pinyin_tone="you3 de5")
    assert not ends_with_particle("目的", pinyin_tone="mu4 di4")
    assert not ends_with_particle("终了", pinyin_tone="zhong1 liao3")
    assert not ends_with_particle("花呢", pinyin_tone="hua1 ni2")
    assert not ends_with_particle("爪哇", pinyin_tone="zhua3 wa1")
    assert not ends_with_particle("哈哈", pinyin_tone="ha1 ha1")


def test_suffix_particle_whitelist_skips_common_phrase() -> None:
    assert ends_with_particle("你的")
    assert is_whitelisted_phrase("你的")


def test_suffix_particle_review_role_separates_core_and_dynamic_candidates() -> None:
    assert particle_suffix_review_role("小小的") == "core_component_candidate"
    assert particle_suffix_review_role("你到底去了哪里呢") == (
        "dynamic_sentence_candidate"
    )


def test_placeholder_phrase_detection() -> None:
    assert is_placeholder_phrase("phrase", "zhong1 guo2", "zhong1 guo2")
    assert not is_placeholder_phrase("phrase", "abc", "zhong1 guo2")
    assert not is_placeholder_phrase("char", "zhong1", "zhong1")


def test_lint_runtime_json_flags_suffix_and_placeholder() -> None:
    report = make_report(sample_limit=10, inputs={"runtime_json": "memory"})
    payload = {
        "by_code": {
            "code-a": [
                {
                    "text": "走了吗",
                    "entry_type": "phrase",
                    "entry_id": "1",
                    "pinyin_tone": "zou3 le5 ma5",
                    "yime_code": "code-a",
                    "sort_weight": 10.0,
                    "is_common": 1,
                    "text_length": 3,
                    "updated_at": "2026-01-01 00:00:00",
                }
            ],
            "zhong1 guo2": [
                {
                    "text": "中国",
                    "entry_type": "phrase",
                    "entry_id": "2",
                    "pinyin_tone": "zhong1 guo2",
                    "yime_code": "zhong1 guo2",
                    "sort_weight": 100.0,
                    "is_common": 1,
                    "text_length": 2,
                    "updated_at": "2026-01-01 00:00:00",
                }
            ],
        }
    }
    lint_runtime_json_payload(payload, report, source_label="memory")
    finalized = finalize_report(report)

    assert finalized["summary"]["candidate_rows"] == 2
    assert finalized["summary"]["suffix_particle_count"] == 1
    assert finalized["summary"]["placeholder_phrase_count"] == 1
    assert "suffix_particle" in finalized["warnings"]
    assert finalized["warnings"]["suffix_particle"][0]["suggested_role"] == (
        "polyfunctional_particle_candidate"
    )
    assert {
        item["system"]
        for item in finalized["warnings"]["suffix_particle"][0][
            "construction_evidence"
        ]
    } == {"aspectual_particles", "modal_particles"}
    assert "placeholder_phrase_code" in finalized["warnings"]


def test_lint_runtime_json_reports_code_key_mismatch_as_error() -> None:
    report = make_report(sample_limit=5, inputs={})
    payload = {
        "by_code": {
            "expected-code": [
                {
                    "text": "测试",
                    "entry_type": "phrase",
                    "entry_id": "9",
                    "pinyin_tone": "ce4 shi4",
                    "yime_code": "other-code",
                    "sort_weight": 3.0,
                    "is_common": 0,
                    "text_length": 2,
                    "updated_at": "2026-01-01 00:00:00",
                }
            ]
        }
    }
    lint_runtime_json_payload(payload, report, source_label="memory")
    finalized = finalize_report(report)
    assert finalized["summary"]["error_count"] == 1
    assert "json_code_key_mismatch" in finalized["errors"]


def test_lint_runtime_db_streams_preferred_materialized_table(tmp_path) -> None:
    db_path = tmp_path / "runtime.db"
    conn = sqlite3.connect(db_path)
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
        INSERT INTO runtime_candidates_materialized VALUES (
            'phrase', '1', '走了吗', 'zou3 le5 ma5', 'code-a',
            10.0, 1, 3, '2026-01-01 00:00:00'
        );
        CREATE VIEW runtime_candidates AS
        SELECT
            'phrase' AS entry_type,
            'legacy' AS entry_id,
            '不应重复扫描吗' AS text,
            'legacy' AS pinyin_tone,
            'legacy' AS yime_code,
            0.0 AS sort_weight,
            0 AS is_common,
            7 AS text_length,
            '2026-01-01 00:00:00' AS updated_at;
        """
    )
    conn.commit()
    conn.close()

    report = make_report(sample_limit=10, inputs={"runtime_db": str(db_path)})
    lint_runtime_db_file(db_path, report)
    finalized = finalize_report(report)

    assert finalized["summary"]["candidate_rows"] == 1
    assert finalized["summary"]["suffix_particle_count"] == 1
    assert finalized["summary"]["error_count"] == 0


def test_lint_runtime_db_missing_file_reports_error_without_creating_it(tmp_path) -> None:
    db_path = tmp_path / "missing.db"
    report = make_report(sample_limit=10, inputs={"runtime_db": str(db_path)})

    lint_runtime_db_file(db_path, report)
    finalized = finalize_report(report)

    assert not db_path.exists()
    assert finalized["summary"]["error_count"] == 1
    assert "runtime_db_read_error" in finalized["errors"]


def test_lint_source_db_streams_phrase_rows(tmp_path) -> None:
    db_path = tmp_path / "source.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE phrase_readings (
            id INTEGER PRIMARY KEY,
            phrase TEXT,
            marked_pinyin TEXT,
            numeric_pinyin TEXT,
            reading_rank INTEGER
        );
        INSERT INTO phrase_readings VALUES
            (1, '好的', 'hǎo de', 'hao3 de5', 1),
            (2, '走了吗', 'zǒu le ma', 'zou3 le5 ma5', 1);
        """
    )
    conn.commit()
    conn.close()

    report = make_report(sample_limit=10, inputs={"source_db": str(db_path)})
    lint_source_db_file(db_path, report)
    finalized = finalize_report(report)

    assert finalized["summary"]["source_phrase_rows"] == 2
    assert finalized["summary"]["warning_count"] == 1
    assert finalized["warnings"]["source_suffix_particle"][0]["phrase"] == "走了吗"


def test_review_samples_are_explicitly_sampled_warnings() -> None:
    report = make_report(sample_limit=1, inputs={})
    payload = {
        "by_code": {
            "code-a": [
                {
                    "text": "去了吗",
                    "entry_type": "phrase",
                    "entry_id": "1",
                    "pinyin_tone": "qu4 le5 ma5",
                    "yime_code": "code-a",
                    "sort_weight": 9.0,
                    "is_common": 1,
                    "text_length": 3,
                    "updated_at": "2026-01-01 00:00:00",
                },
                {
                    "text": "走了吗",
                    "entry_type": "phrase",
                    "entry_id": "2",
                    "pinyin_tone": "zou3 le5 ma5",
                    "yime_code": "code-a",
                    "sort_weight": 10.0,
                    "is_common": 1,
                    "text_length": 3,
                    "updated_at": "2026-01-01 00:00:00",
                },
            ]
        }
    }
    lint_runtime_json_payload(payload, report, source_label="memory")
    finalized = finalize_report(report)

    assert finalized["summary"]["warning_count"] == 2
    review_samples = list(iter_review_samples(finalized))
    assert len(review_samples) == 1
    assert review_samples[0]["text"] == "走了吗"
