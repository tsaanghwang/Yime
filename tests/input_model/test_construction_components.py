from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from yime.input_model.construction_components import (
    ConstructionFamily,
    construction_family,
    evaluate_prebuilt_component,
    plan_construction_components,
)


def _policy(path: Path, *, minimum_improved: int = 1) -> Path:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "maximum_component_length": 4,
                "families": {},
                "cache_gate": {
                    "minimum_dependent_reading_count": 2,
                    "minimum_ab_improved_target_readings": minimum_improved,
                    "minimum_ab_improvement_ratio": 0.5,
                    "maximum_structural_competition_ratio": 0.1,
                    "require_all_readings_dynamically_recoverable": True,
                    "role_after_gate": "component_only",
                    "fallback_role": "runtime_generated",
                },
                "safeguards": {
                    "source_readings_only": True,
                    "fixed_lexical_decisions_override_family_rules": True,
                },
            }
        ),
        encoding="utf-8",
    )
    return path


def _source(path: Path, entries: list[tuple[str, str, int]]) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE canonical_readings (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                text_length INTEGER NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                pronunciation_scope TEXT NOT NULL
            );
            CREATE INDEX canonical_text_numeric
                ON canonical_readings(text, numeric_pinyin);
            """
        )
        connection.executemany(
            """
            INSERT INTO canonical_readings (
                text, text_length, numeric_pinyin, reading_rank,
                bcc_frequency, pronunciation_scope
            ) VALUES (?, LENGTH(?), ?, 1, ?, 'standalone')
            """,
            [(text, text, numeric, frequency) for text, numeric, frequency in entries],
        )
    return path


def _capacity(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE static_capacity_items (
                text TEXT PRIMARY KEY,
                text_length INTEGER NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                reading_count INTEGER NOT NULL,
                recoverable_reading_count INTEGER NOT NULL,
                mandatory_static INTEGER NOT NULL,
                dependent_reading_count INTEGER NOT NULL,
                dependent_frequency INTEGER NOT NULL,
                utility_score REAL NOT NULL,
                recommended_disposition TEXT NOT NULL
            );
            CREATE TABLE reading_analysis (
                text TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                is_primary INTEGER NOT NULL
            );
            INSERT INTO static_capacity_items VALUES
                ('般的', 2, 100, 1, 1, 0, 3, 0, 5.0, 'selected_static'),
                ('所说', 2, 80, 1, 1, 0, 2, 0, 4.0, 'selected_static');
            INSERT INTO reading_analysis VALUES
                ('般的', 'ban1 de5', 1),
                ('所说', 'suo3 shuo1', 1);
            """
        )
    return path


def test_construction_family_requires_anchor_reading() -> None:
    assert construction_family("般的", "ban1 de5") is ConstructionFamily.DE
    assert construction_family("所说", "suo3 shuo1") is ConstructionFamily.SUO
    assert construction_family("目的", "mu4 di4") is None
    assert construction_family("所以", "suo2 yi3") is None


def test_planner_routes_recoverable_reused_candidates_to_component_cache(
    tmp_path: Path,
) -> None:
    candidates = plan_construction_components(
        capacity_database=_capacity(tmp_path / "capacity.sqlite3"),
        policy_path=_policy(tmp_path / "policy.json"),
    )
    assert {(item.text, item.proposed_role) for item in candidates} == {
        ("般的", "component_only_candidate"),
        ("所说", "component_only_candidate"),
    }


def test_reviewed_ab_rejection_overrides_dependency_heuristic(
    tmp_path: Path,
) -> None:
    decisions = tmp_path / "decisions.json"
    decisions.write_text(
        json.dumps(
            {
                "batches": [
                    {
                        "decisions": [
                            {
                                "text": "般的",
                                "decision_status": "deferred",
                                "integration_policy": "needs_review",
                                "candidate_class": "semi_fixed_construction",
                                "rationale": "A/B 拒绝预制。",
                                "evidence": {
                                    "prebuilt_component_decision": (
                                        "do_not_prebuild_use_runtime_generation"
                                    )
                                },
                            }
                        ]
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    candidates = plan_construction_components(
        capacity_database=_capacity(tmp_path / "capacity.sqlite3"),
        policy_path=_policy(tmp_path / "policy.json"),
        decision_catalog=decisions,
    )
    role_by_text = {item.text: item.proposed_role for item in candidates}
    assert role_by_text["般的"] == "runtime_generated"
    assert role_by_text["所说"] == "component_only_candidate"


def test_ab_rejects_prebuild_that_only_adds_equal_length_ambiguity(
    tmp_path: Path,
) -> None:
    source = _source(
        tmp_path / "source.sqlite3",
        [
            ("天", "tian1", 0),
            ("使", "shi3", 0),
            ("天使", "tian1 shi3", 0),
            ("般", "ban1", 0),
            ("的", "de5", 0),
            ("般的", "ban1 de5", 100),
            ("天使般", "tian1 shi3 ban1", 0),
            ("天使般的", "tian1 shi3 ban1 de5", 10),
        ],
    )
    result = evaluate_prebuilt_component(
        source_database=source,
        policy_path=_policy(tmp_path / "policy.json"),
        component_text="般的",
        component_numeric_pinyin="ban1 de5",
    )
    assert result["metrics"]["minimum_part_count_improved"] == 0
    assert result["metrics"]["new_minimum_segmentation_ambiguities"] == 1
    assert result["decision"] == "do_not_prebuild_use_runtime_generation"


def test_ab_keeps_prebuild_when_it_reduces_parts_without_ambiguity(
    tmp_path: Path,
) -> None:
    source = _source(
        tmp_path / "source.sqlite3",
        [
            ("梦幻", "meng4 huan4", 0),
            ("般", "ban1", 0),
            ("的", "de5", 0),
            ("般的", "ban1 de5", 100),
            ("梦幻般的", "meng4 huan4 ban1 de5", 10),
        ],
    )
    result = evaluate_prebuilt_component(
        source_database=source,
        policy_path=_policy(tmp_path / "policy.json"),
        component_text="般的",
        component_numeric_pinyin="ban1 de5",
    )
    assert result["metrics"]["minimum_part_count_improved"] == 1
    assert result["metrics"]["new_minimum_segmentation_ambiguities"] == 0
    assert result["decision"] == "keep_as_component_only"


def test_ab_accepts_small_same_output_structural_competition(
    tmp_path: Path,
) -> None:
    policy = json.loads(_policy(tmp_path / "policy.json").read_text())
    policy["families"] = {
        "de_construction": {
            "display_and_component_texts": ["似的"],
        }
    }
    (tmp_path / "policy.json").write_text(
        json.dumps(policy, ensure_ascii=False),
        encoding="utf-8",
    )
    entries = [
        ("似", "shi4", 0),
        ("的", "de5", 0),
        ("似的", "shi4 de5", 100),
    ]
    for index in range(20):
        prefix = chr(0x4E00 + index)
        entries.extend(
            [
                (prefix, f"x{index}", 0),
                (
                    f"{prefix}似的",
                    f"x{index} shi4 de5",
                    0,
                ),
            ]
        )
    # One target has an equal-length alternate prefix path; runtime state
    # pruning still exposes only one candidate for the same final text.
    entries.append((f"{chr(0x4E00)}似", "x0 shi4", 0))
    result = evaluate_prebuilt_component(
        source_database=_source(tmp_path / "source.sqlite3", entries),
        policy_path=tmp_path / "policy.json",
        component_text="似的",
        component_numeric_pinyin="shi4 de5",
    )
    assert result["metrics"]["minimum_part_count_improved"] == 19
    assert result["metrics"]["new_minimum_segmentation_ambiguities"] == 1
    assert result["metrics"]["structural_competition_ratio"] == 0.05
    assert result["metrics"]["user_visible_output_ambiguities"] == 0
    assert result["decision"] == "keep_as_display_and_component"
