from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from yime.input_model import (
    RecursiveCompositionConfig,
    UnencodedCandidateReview,
    build_input_model,
    build_recursive_composition_model,
)
from yime.input_model.recursive_composition import _materialize_segments


ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "internal_data" / "input_candidate_model_policy.json"


def test_layered_fallback_absorbs_single_and_uses_four_when_it_preserves_triplet(
) -> None:
    segments = _materialize_segments(
        (("encoded_multichar", "中国人"), ("residual", "银")),
        {"中", "国", "人", "银", "中国", "中国人"},
    )

    assert segments == (
        {
            "kind": "dynamic_residual_block",
            "text": "中国人银",
            "fallback_size": 4,
            "internal_parts": ["中国人", "银"],
            "missing_characters": [],
        },
    )


def _source_database(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE accepted_readings (
                text TEXT NOT NULL,
                source TEXT NOT NULL,
                source_category TEXT NOT NULL
            );
            CREATE TABLE canonical_readings (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL,
                reading_source_categories TEXT NOT NULL,
                pronunciation_scope TEXT NOT NULL,
                neutral_tone_positions TEXT NOT NULL,
                neutral_tone_status TEXT NOT NULL
            );
            CREATE INDEX canonical_text_rank_idx
                ON canonical_readings(text, reading_rank);
            CREATE TABLE bcc_frequency (
                text TEXT PRIMARY KEY,
                frequency INTEGER NOT NULL
            );
            CREATE TABLE rejections (
                text TEXT NOT NULL,
                reason TEXT NOT NULL
            );
            """
        )
        connection.executemany(
            """
            INSERT INTO canonical_readings VALUES (
                ?, ?, ?, ?, ?, ?, ?, 'test', 'test:component',
                'standalone', '', 'none'
            )
            """,
            [
                (1, "中", "zhōng", "zhong1", 1, 1, 10_000),
                (2, "国", "guó", "guo2", 1, 1, 9_000),
                (3, "人", "rén", "ren2", 1, 1, 8_000),
                (4, "民", "mín", "min2", 1, 1, 7_000),
                (5, "银", "yín", "yin2", 1, 1, 6_000),
                (6, "行", "xíng", "xing2", 1, 1, 5_000),
                (7, "行", "háng", "hang2", 2, 0, 5_000),
                (
                    8,
                    "中国",
                    "zhōng guó",
                    "zhong1 guo2",
                    1,
                    1,
                    4_000,
                ),
                (
                    9,
                    "人民",
                    "rén mín",
                    "ren2 min2",
                    1,
                    1,
                    3_000,
                ),
            ],
        )
        connection.executemany(
            "INSERT INTO bcc_frequency VALUES (?, ?)",
            [
                ("中国人民", 20_000),
                ("银行", 19_000),
                ("中国人民银行", 18_000),
                ("中国𠮷", 17_000),
                ("中国人", 16_000),
            ],
        )
    return path


def test_recursive_model_uses_gated_components_without_manual_labels(
    tmp_path: Path,
) -> None:
    source = _source_database(tmp_path / "source.sqlite3")
    input_model = tmp_path / "input_model.sqlite3"
    build_input_model(
        source_database=source,
        output_database=input_model,
        policy_path=POLICY,
    )
    result = build_recursive_composition_model(
        source_database=source,
        input_model_database=input_model,
        output_dir=tmp_path / "recursive",
        config=RecursiveCompositionConfig(maximum_parts_per_step=2),
    )

    assert result.target_count == 5
    assert result.reachable_count == 4
    assert result.unreachable_count == 1
    assert result.uses_multichar_component_count == 3
    assert result.residual_blocks_only_count == 1
    assert result.single_exception_target_count == 1

    with sqlite3.connect(input_model) as connection:
        connection.row_factory = sqlite3.Row
        people = connection.execute(
            """
            SELECT * FROM recursive_composition_evidence
            WHERE text = '中国人民'
            """
        ).fetchone()
        bank = connection.execute(
            """
            SELECT * FROM recursive_composition_evidence
            WHERE text = '银行'
            """
        ).fetchone()
        long_target = connection.execute(
            """
            SELECT * FROM recursive_composition_evidence
            WHERE text = '中国人民银行'
            """
        ).fetchone()
        blocked = connection.execute(
            """
            SELECT * FROM recursive_composition_evidence
            WHERE text = '中国𠮷'
            """
        ).fetchone()
        no_exposed_single = connection.execute(
            """
            SELECT * FROM recursive_composition_evidence
            WHERE text = '中国人'
            """
        ).fetchone()
        dispositions = dict(
            connection.execute(
                """
                SELECT text, baseline_status
                FROM candidate_universe
                WHERE has_gated_reading = 0
                """
            )
        )

    assert json.loads(people["preferred_parts_json"]) == ["中国", "人民"]
    assert people["minimum_leaf_parts"] == 2
    assert people["changes_candidate_disposition"] == 0
    assert people["primary_numeric_input"] == "zhong1 guo2 ren2 min2"

    assert json.loads(bank["preferred_parts_json"]) == ["银行"]
    assert json.loads(bank["preferred_segments_json"]) == [
        {
            "kind": "dynamic_residual_block",
            "text": "银行",
            "fallback_size": 2,
            "internal_parts": ["银", "行"],
            "missing_characters": [],
        }
    ]
    assert bank["reading_combination_count"] == "2"
    assert bank["reading_ambiguous"] == 1
    assert bank["primary_numeric_input"] == "yin2 xing2"

    assert json.loads(long_target["preferred_parts_json"]) == [
        "中国",
        "人民",
        "银行",
    ]
    assert long_target["recursive_depth"] == 2
    assert json.loads(no_exposed_single["preferred_segments_json"]) == [
        {
            "kind": "dynamic_residual_block",
            "text": "中国人",
            "fallback_size": 3,
            "internal_parts": ["中国", "人"],
            "missing_characters": [],
        }
    ]

    blocker = json.loads(blocked["blocker_json"])
    assert blocked["reachability_status"] == "unreachable"
    assert blocker["missing_standalone_characters"] == [
        {"text": "𠮷", "codepoint": "U+20BB7"}
    ]
    assert set(dispositions.values()) == {"proposed"}

    review = UnencodedCandidateReview(
        input_model_database=input_model,
        source_database=source,
    )
    detail = review.detail("银行")
    assert detail["decision_status"] == "proposed"
    assert detail["recursive_composition"]["preferred_parts"] == ["银行"]
    assert detail["recursive_composition"]["preferred_segments"][0]["kind"] == (
        "dynamic_residual_block"
    )
    assert detail["recursive_composition"]["creates_whole_string_reading"] is False
    recursive_summary = review.summary()["recursive_composition"]
    assert recursive_summary["reachable"] == 4
    assert recursive_summary["uses_multichar_component"] == 3
    assert recursive_summary["residual_blocks_only"] == 1
    assert recursive_summary["single_exception_targets"] == 1

    manifest = json.loads(result.manifest.read_text(encoding="utf-8"))
    assert manifest["semantics"]["components_require_manual_label"] is False
    assert manifest["semantics"]["target_whole_reading_is_not_created"] is True
    assert manifest["semantics"]["top_level_single_components_allowed"] is False
    assert manifest["semantics"]["default_residual_block_size"] == 2
    assert result.evidence_tsv.is_file()
    assert result.summary_markdown.is_file()

    build_input_model(
        source_database=source,
        output_database=input_model,
        policy_path=POLICY,
    )
    with sqlite3.connect(input_model) as connection:
        assert connection.execute(
            "SELECT COUNT(*) FROM recursive_composition_evidence"
        ).fetchone()[0] == 0
