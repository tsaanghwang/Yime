from __future__ import annotations

import importlib.util
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "tools"
    / "generate_local_phrase_priority_baseline.py"
)
SPEC = importlib.util.spec_from_file_location(
    "generate_local_phrase_priority_baseline",
    MODULE_PATH,
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

_fragment_penalty = MODULE._fragment_penalty
_build_sample_bucket_entry = MODULE._build_sample_bucket_entry
_build_continuous_rules_payload = MODULE._build_continuous_rules_payload
_iter_continuous_lookup_codes = MODULE._iter_continuous_lookup_codes
_rank_prefix_phrases = MODULE._rank_prefix_phrases


def test_fragment_penalty_marks_obvious_suffix_fragments() -> None:
    assert _fragment_penalty("技术的") > _fragment_penalty("技术")
    assert _fragment_penalty("必要的") > _fragment_penalty("必要")
    assert _fragment_penalty("吸引了") > _fragment_penalty("吸引")
    assert _fragment_penalty("是一个") > _fragment_penalty("市场")


def test_rank_prefix_phrases_prefers_strict_words_over_fragment_tails() -> None:
    ranked = _rank_prefix_phrases(
        [
            {"phrase": "希望", "phrase_frequency": 577147.0, "reading_rank": 1},
            {"phrase": "吸引", "phrase_frequency": 243212.0, "reading_rank": 1},
            {"phrase": "嘻嘻", "phrase_frequency": 123165.0, "reading_rank": 1},
            {"phrase": "西班牙", "phrase_frequency": 114461.0, "reading_rank": 1},
            {"phrase": "希望能", "phrase_frequency": 108189.0, "reading_rank": 1},
            {"phrase": "吸引了", "phrase_frequency": 82959.0, "reading_rank": 1},
            {"phrase": "吸收", "phrase_frequency": 76729.0, "reading_rank": 1},
            {"phrase": "西方", "phrase_frequency": 76494.0, "reading_rank": 1},
        ]
    )

    assert [entry["phrase"] for entry in ranked[:6]] == [
        "希望",
        "吸引",
        "嘻嘻",
        "西班牙",
        "吸收",
        "西方",
    ]


def test_build_sample_bucket_entry_keeps_collision_metadata_and_targets() -> None:
    entry = _build_sample_bucket_entry(
        {
            "candidate_count": 513,
            "demand_weight_sum": 72416.0,
            "collision_demand_score": 37149408.0,
            "top_current_runtime_texts": ["一", "食", "意"],
        },
        lookup_code="abcd",
        lookup_pinyin_tone="yi4",
        prefix_phrases=[
            {"phrase": "一般"},
            {"phrase": "一直"},
        ],
        targets=[
            {"text": "一般", "boost": 500000.0},
            {"text": "一直", "boost": 400000.0},
        ],
    )

    assert entry == {
        "lookup_code": "abcd",
        "lookup_pinyin_tone": "yi4",
        "candidate_count": 513,
        "demand_weight_sum": 72416.0,
        "collision_demand_score": 37149408.0,
        "top_current_runtime_texts": ["一", "食", "意"],
        "target_phrases": ["一般", "一直"],
        "sample_phrases": ["一般", "一直"],
    }


def test_iter_continuous_lookup_codes_expands_to_all_prefixes_after_first_syllable() -> None:
    assert _iter_continuous_lookup_codes("abcdxywv") == [
        "abcdxy",
        "abcdxyw",
    ]
    assert _iter_continuous_lookup_codes("abcdefghijkl") == [
        "abcdefghi",
        "abcdefghij",
        "abcdefghijk",
    ]
    assert _iter_continuous_lookup_codes("abcd") == []


def test_build_continuous_rules_payload_expands_target_phrase_codes() -> None:
    payload = _build_continuous_rules_payload(
        [
            {
                "targets": [
                    {"text": "你好啊", "yime_code": "abcdxywv", "boost": 500000.0},
                    {"text": "你好吗", "yime_code": "abcdefghijkl", "boost": 400000.0},
                ]
            }
        ],
        source="test-source",
    )

    assert payload["scope"] == "continuous_input_prefix"
    assert payload["source"] == "test-source"
    assert payload["rules"] == [
        {
            "lookup_code": "abcdefghi",
            "targets": [
                {"text": "你好吗", "boost": 400000.0},
            ],
        },
        {
            "lookup_code": "abcdefghij",
            "targets": [
                {"text": "你好吗", "boost": 400000.0},
            ],
        },
        {
            "lookup_code": "abcdefghijk",
            "targets": [
                {"text": "你好吗", "boost": 400000.0},
            ],
        },
        {
            "lookup_code": "abcdxy",
            "targets": [
                {"text": "你好啊", "boost": 500000.0},
            ],
        },
        {
            "lookup_code": "abcdxyw",
            "targets": [
                {"text": "你好啊", "boost": 500000.0},
            ],
        },
    ]
