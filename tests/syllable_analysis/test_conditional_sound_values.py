import json
from pathlib import Path

from syllable.analysis.conditional_sound_values import (
    DEFAULT_MODEL_PATH,
    PROJECT_ROOT,
    audit_conditional_sound_value_model,
)


def test_current_conditional_sound_value_source_chain_is_complete() -> None:
    result = audit_conditional_sound_value_model()

    assert result.passed, result.issues
    assert result.zaoyin_count == 27
    assert result.zaoyin_registered_count == 27
    assert result.yueyin_count == 33
    assert result.zaoyin_count + result.yueyin_count == 60
    assert result.conditional_rule_count == 0
    assert result.runtime_enabled is False


def test_unknown_yinyuan_id_in_rule_is_rejected(tmp_path: Path) -> None:
    model = json.loads(DEFAULT_MODEL_PATH.read_text(encoding="utf-8"))
    model["conditional_rules"] = [
        {
            "rule_id": "invalid-target-example",
            "activation": "research_only",
            "source_refs": ["test-only"],
            "conditions": {"syllable_index": 0},
            "operations": [
                {
                    "type": "substitute_yinyuan",
                    "source_yinyuan_id": "M01",
                    "target_yinyuan_id": "M99",
                }
            ],
        }
    ]
    model_path = tmp_path / "model.json"
    model_path.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")

    result = audit_conditional_sound_value_model(model_path, PROJECT_ROOT)

    assert not result.passed
    assert any("M99" in issue for issue in result.issues)


def test_runtime_enablement_is_rejected(tmp_path: Path) -> None:
    model = json.loads(DEFAULT_MODEL_PATH.read_text(encoding="utf-8"))
    model["runtime_enabled"] = True
    model_path = tmp_path / "model.json"
    model_path.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")

    result = audit_conditional_sound_value_model(model_path, PROJECT_ROOT)

    assert not result.passed
    assert any("runtime_enabled" in issue for issue in result.issues)
