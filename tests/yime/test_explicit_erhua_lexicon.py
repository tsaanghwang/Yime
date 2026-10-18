from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from yime.connected_speech.erhua_lexicon import (
    DEFAULT_ALIASES,
    DEFAULT_ANNOTATIONS,
    build_explicit_erhua_bundles,
    is_explicit_word_final_erhua,
)


ROOT = Path(__file__).resolve().parents[2]


def _fixture(*, text: str, numeric_pinyin: str, source_kind: str) -> dict:
    return {
        "text": text,
        "numeric_pinyin": numeric_pinyin,
        "evidence": [{
            "source_kind": source_kind,
            "source_key": "fixture",
            "review_state": "confirmed",
            "source_pinyin": "huār",
        }],
    }


def test_admission_requires_explicit_evidence_and_word_final_written_er() -> None:
    assert is_explicit_word_final_erhua(
        _fixture(text="花儿", numeric_pinyin="hua1 er5", source_kind="psc_erhua")
    )
    assert not is_explicit_word_final_erhua(
        _fixture(text="花儿", numeric_pinyin="hua1 er5", source_kind="psc_passage")
    )
    assert not is_explicit_word_final_erhua(
        _fixture(text="高跟儿鞋", numeric_pinyin="gao1 gen1 er5 xie2", source_kind="psc_erhua")
    )
    assert not is_explicit_word_final_erhua(
        _fixture(text="花", numeric_pinyin="hua1 er5", source_kind="psc_erhua")
    )
    assert not is_explicit_word_final_erhua(
        _fixture(text="花儿", numeric_pinyin="hua1 er2", source_kind="psc_erhua")
    )


def test_real_catalog_builds_only_explicit_non_productive_records() -> None:
    annotations, aliases = build_explicit_erhua_bundles(
        repo_root=ROOT,
        generated_at=datetime(2026, 8, 15, tzinfo=timezone.utc),
    )
    assert annotations["runtime_enabled"] is False
    assert aliases["runtime_enabled"] is False
    assert annotations["counts"]["explicit_erhua_evidence_records"] == 132
    assert annotations["counts"]["admitted_word_final_records"] == 131
    assert annotations["counts"]["excluded_explicit_records"] == 1
    assert aliases["counts"]["records"] == 131
    assert aliases["counts"]["feature_projection_ready"] == 131
    assert aliases["counts"].get("suffix_only_encoding_pending", 0) == 0
    assert aliases["erhua_yinyuan_feature_source"] == "external_data/erhua_yinyuan_feature_rules.json"
    assert "erhua_surface_source" not in aliases
    assert all(item["text"].endswith("儿") for item in annotations["records"])
    assert all(item["productive_inference"] == "forbidden" for item in annotations["records"])
    assert "鸟儿" not in {item["text"] for item in annotations["records"]}
    assert annotations["excluded_explicit_records"] == [
        {
            "text": "高跟儿鞋",
            "numeric_pinyin": "gao1 gen1 er5 xie2",
            "reason": "not_at_least_one_han_plus_word_final_er",
        }
    ]

    annotation_by_id = {item["record_id"]: item for item in annotations["records"]}
    assert set(annotation_by_id) == {item["record_id"] for item in aliases["records"]}
    for item in aliases["records"]:
        assert item["candidate_text_mutation"] == "forbidden"
        suffix = item["routes"]["suffix_compatibility"]
        assert suffix["status"] == "available"
        for mode in ("full", "variable", "shorthand"):
            assert suffix["codes"][mode]["layout_key_code"]
        fused = item["routes"]["fused_erhua"]
        if item["status"] == "feature_projection_ready":
            assert fused["status"] == "feature_projection_ready"
            assert fused["feature_rule_id"].startswith("ERHUA-YINYUAN-")
            assert len(fused["attached_syllable_source_yinyuan_ids"]) == 4
            assert fused["feature_rewrites"]
            assert "codes" not in fused
            assert "surface_class" not in fused
        else:
            assert fused["status"] == "encoding_pending"
            assert "codes" not in fused

    by_text = {item["text"]: item for item in aliases["records"]}
    for text, expected in {
        "鱼漂儿": [(2, "M10", False), (3, "M04", False)],
        "棉球儿": [(2, "M14", False), (3, "M04", False)],
        "小鞋儿": [(2, "M23", False), (3, "M22", False)],
        "雨点儿": [(2, "M12", False), (3, "M12", False)],
        "火锅儿": [(2, "M13", False), (3, "M13", False)],
        "红包儿": [(2, "M10", False), (3, "M04", False)],
        "衣兜儿": [(2, "M13", False), (3, "M04", False)],
        "泪珠儿": [(2, "M04", False), (3, "M04", False)],
    }.items():
        rewrites = by_text[text]["routes"]["fused_erhua"]["feature_rewrites"]
        assert [
            (row["position"], row["base_yinyuan_id"], row["features"]["nasalized"])
            for row in rewrites
        ] == expected


def test_checked_in_bundles_are_complete_and_current() -> None:
    expected_annotations, expected_aliases = build_explicit_erhua_bundles(
        repo_root=ROOT,
        generated_at=datetime(2026, 8, 15, tzinfo=timezone.utc),
    )
    actual_annotations = json.loads((ROOT / DEFAULT_ANNOTATIONS).read_text(encoding="utf-8"))
    actual_aliases = json.loads((ROOT / DEFAULT_ALIASES).read_text(encoding="utf-8"))
    for payload in (actual_annotations, actual_aliases):
        payload["generated_utc"] = "2026-08-15T00:00:00Z"
    assert actual_annotations == expected_annotations
    assert actual_aliases == expected_aliases
