from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_runtime_build_requires_dynamic_coverage_gate() -> None:
    policy = json.loads(
        (
            ROOT / "internal_data" / "runtime_lexicon_filter_policy.json"
        ).read_text(encoding="utf-8")
    )
    gate = policy["dynamic_coverage_gate"]
    assert gate == {
        "policy": "internal_data/dynamic_candidate_coverage_policy.json",
        "require_complete": True,
    }
    build_script = (
        ROOT / "tools" / "build_two_level_runtime_trial.py"
    ).read_text(encoding="utf-8")
    assert "evaluate_dynamic_candidate_coverage(" in build_script
    assert '"dynamic_candidate_coverage"' in build_script


def test_phase_43_is_closed_without_obsolete_cleanup_plan() -> None:
    obsolete_name = "LEXICON_" + "CLEANUP_EXECUTION.md"
    assert not (ROOT / "docs" / obsolete_name).exists()
    completion_doc = (
        ROOT / "docs" / "DYNAMIC_CANDIDATE_COVERAGE.md"
    ).read_text(encoding="utf-8")
    roadmap = (
        ROOT / "docs" / "CANDIDATE_CORPUS_ROADMAP.md"
    ).read_text(encoding="utf-8")
    project_roadmap = (
        ROOT / "docs" / "project" / "ROADMAP.md"
    ).read_text(encoding="utf-8")
    assert "R0 | 0" in completion_doc
    assert "以上程序门禁已经满足" in completion_doc
    assert obsolete_name.removesuffix(".md") not in roadmap
    assert "候选池动态覆盖闭环（已完成）" in project_roadmap
