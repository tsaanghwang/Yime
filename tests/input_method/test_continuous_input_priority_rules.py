from __future__ import annotations

from pathlib import Path

from yime.input_method.core.char_code_index import CharCodeIndex
from yime.input_method.core.decoders import RuntimeCandidateDecoder
from yime.input_method.core.runtime_ranking import load_local_phrase_priority_rules


FIRST_PAGE_CANDIDATE_LIMIT = 5


def _build_runtime_decoder(*, debug_runtime_ranking: bool = True) -> RuntimeCandidateDecoder:
    runtime_decoder = RuntimeCandidateDecoder.__new__(RuntimeCandidateDecoder)
    runtime_decoder.bmp_to_canonical = {}
    runtime_decoder.numeric_to_marked_pinyin = {}
    runtime_decoder.debug_runtime_ranking = debug_runtime_ranking
    runtime_decoder._user_freq_by_candidate = {}
    runtime_decoder._local_phrase_priority_rules = {}
    runtime_decoder._continuous_input_priority_rules = {}
    runtime_decoder.by_code = {}
    runtime_decoder._char_sort_weight_by_text = {}
    runtime_decoder._phrase_prefix_index = {}
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)
    return runtime_decoder


def _load_generated_continuous_rules() -> dict[str, dict[str, float]]:
    return load_local_phrase_priority_rules(
        Path(__file__).resolve().parents[2] / "internal_data" / "continuous_input_priority_rules.json",
        {},
        lambda _pinyin_tone, _pinyin_to_canonical: "",
        expected_lookup_code_length=None,
        min_lookup_code_length=5,
    )


def _find_generated_rule_by_targets(
    rules: dict[str, dict[str, float]],
    expected_targets: set[str],
) -> tuple[str, dict[str, float]]:
    for lookup_code, targets in rules.items():
        if set(targets) == expected_targets:
            return lookup_code, targets
    raise AssertionError(f"missing generated rule for targets={sorted(expected_targets)}")


def _build_ranked_prefix_candidates(lookup_code: str, target_texts: list[str]) -> list[dict[str, object]]:
    candidates: list[dict[str, object]] = []
    for index in range(3):
        candidates.append(
            {
                "text": f"占位词{index + 1}",
                "entry_type": "phrase",
                "pinyin_tone": f"zhan4 wei4 ci2 {index + 1}",
                "yime_code": lookup_code + chr(ord("a") + index),
                "sort_weight": 999.0 - index,
                "text_length": 4,
                "is_common": 1,
            }
        )
    for index, text in enumerate(target_texts):
        candidates.append(
            {
                "text": text,
                "entry_type": "phrase",
                "pinyin_tone": "generated target",
                "yime_code": lookup_code + chr(ord("d") + index),
                "sort_weight": 100.0 - index,
                "text_length": max(len(text), 2),
                "is_common": 1,
            }
        )
    candidates.append(
        {
            "text": "占位词尾",
            "entry_type": "phrase",
            "pinyin_tone": "zhan4 wei4 ci2 wei3",
            "yime_code": lookup_code + "z",
            "sort_weight": 50.0,
            "text_length": 4,
            "is_common": 1,
        }
    )
    return candidates


def _assert_targets_stay_on_first_page(candidates: list[str], target_texts: list[str]) -> None:
    assert candidates[: len(target_texts)] == target_texts
    assert set(candidates[:FIRST_PAGE_CANDIDATE_LIMIT]) >= set(target_texts)


def _assert_generated_rule_targets_stay_on_first_page(expected_targets: set[str]) -> None:
    runtime_decoder = _build_runtime_decoder()
    generated_rules = _load_generated_continuous_rules()
    runtime_decoder._continuous_input_priority_rules = generated_rules

    lookup_code, targets = _find_generated_rule_by_targets(generated_rules, expected_targets)
    target_texts = list(targets)
    runtime_decoder._phrase_prefix_index = {
        lookup_code: _build_ranked_prefix_candidates(lookup_code, target_texts)
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text(lookup_code)

    _assert_targets_stay_on_first_page(candidates, target_texts)
    for text in target_texts:
        assert f"{text}[prefix/C-continuous]" in status


def test_continuous_input_context_rule_promotes_partial_phrase() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._continuous_input_priority_rules = {
        "abcdxy": {
            "你好啊": 500.0,
        }
    }
    runtime_decoder._phrase_prefix_index = {
        "abcdxy": [
            {
                "text": "你好吗",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 ma5",
                "yime_code": "abcdxyzz",
                "sort_weight": 320.0,
                "text_length": 3,
                "is_common": 1,
            },
            {
                "text": "你好啊",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 a5",
                "yime_code": "abcdxywv",
                "sort_weight": 280.0,
                "text_length": 3,
                "is_common": 1,
            },
        ]
    }

    canonical, active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdxy")

    assert canonical == "abcdxy"
    assert active == "abcd"
    assert candidates[:2] == ["你好啊", "你好吗"]
    assert "已完成 1 个音节" in status
    assert "[long-context-prefix-1]" in status
    assert "你好啊[prefix/C-continuous]" in status
    assert "你好吗[prefix/normal]" in status


def test_runtime_debug_summary_is_opt_in() -> None:
    runtime_decoder = _build_runtime_decoder(debug_runtime_ranking=False)
    runtime_decoder._continuous_input_priority_rules = {
        "abcdxy": {
            "你好啊": 500.0,
        }
    }
    runtime_decoder._phrase_prefix_index = {
        "abcdxy": [
            {
                "text": "你好啊",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 a5",
                "yime_code": "abcdxywv",
                "sort_weight": 280.0,
                "text_length": 3,
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, _candidates, status = runtime_decoder.decode_text("abcdxy")

    assert "调试:" not in status


def test_continuous_input_context_rule_promotes_exact_multisyllable_phrase() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._continuous_input_priority_rules = {
        "abcdefgh": {
            "你好": 500.0,
        }
    }
    runtime_decoder.by_code = {
        "abcdefgh": [
            {
                "text": "你号",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao4",
                "yime_code": "abcdefgh",
                "sort_weight": 320.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "你好",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3",
                "yime_code": "abcdefgh",
                "sort_weight": 280.0,
                "text_length": 2,
                "is_common": 1,
            },
        ]
    }
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)

    canonical, active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdefgh")

    assert canonical == "abcdefgh"
    assert active == "abcdefgh"
    assert candidates[:2] == ["你好", "你号"]
    assert "音节" in status
    assert "你好[exact/D-continuous]" in status
    assert "你号[exact/normal]" in status


def test_stage_b_prefers_local_phrase_priority_over_continuous_context_priority() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._local_phrase_priority_rules = {
        "abcd": {
            "你号": 500.0,
        }
    }
    runtime_decoder._continuous_input_priority_rules = {
        "abcd": {
            "你好": 900.0,
        }
    }
    runtime_decoder.by_code = {
        "abcd": [
            {
                "text": "你",
                "entry_type": "char",
                "pinyin_tone": "ni3",
                "yime_code": "abcd",
                "sort_weight": 999.0,
                "text_length": 1,
                "is_common": 1,
            }
        ]
    }
    runtime_decoder._phrase_prefix_index = {
        "abcd": [
            {
                "text": "你好",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3",
                "yime_code": "abcdwxyz",
                "sort_weight": 320.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "你号",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao4",
                "yime_code": "abcdwvut",
                "sort_weight": 280.0,
                "text_length": 2,
                "is_common": 1,
            },
        ]
    }
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text("abcd")

    assert candidates[:2] == ["你号", "你好"]
    assert "你号[prefix/B-local]" in status
    assert "你好[prefix/B-continuous]" in status
    assert "你[exact/normal]" in status


def test_stage_c_prefers_continuous_context_priority_over_local_phrase_priority() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._local_phrase_priority_rules = {
        "abcdxy": {
            "你好吗": 500.0,
        }
    }
    runtime_decoder._continuous_input_priority_rules = {
        "abcdxy": {
            "你好啊": 900.0,
        }
    }
    runtime_decoder._phrase_prefix_index = {
        "abcdxy": [
            {
                "text": "你好吗",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 ma5",
                "yime_code": "abcdxyzz",
                "sort_weight": 320.0,
                "text_length": 3,
                "is_common": 1,
            },
            {
                "text": "你好啊",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 a5",
                "yime_code": "abcdxywv",
                "sort_weight": 280.0,
                "text_length": 3,
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdxy")

    assert candidates[:2] == ["你好啊", "你好吗"]
    assert "[long-context-prefix-1]" in status
    assert "你好啊[prefix/C-continuous]" in status
    assert "你好吗[prefix/C-local]" in status


def test_stage_c_debug_status_shows_long_context_prefix_2() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._continuous_input_priority_rules = {
        "abcdefghxy": {
            "中长词00": 500.0,
        }
    }
    runtime_decoder._phrase_prefix_index = {
        "abcdefghxy": [
            {
                "text": "中长词00",
                "entry_type": "phrase",
                "pinyin_tone": "zhong1 chang2 ci2",
                "yime_code": "abcdefghxyzz",
                "sort_weight": 280.0,
                "text_length": 4,
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdefghxy")

    assert candidates == ["中长词00"]
    assert "[long-context-prefix-2]" in status
    assert "中长词00[prefix/C-continuous]" in status


def test_stage_c_debug_status_shows_long_context_prefix_3() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._continuous_input_priority_rules = {
        "abcdefghijklxy": {
            "超长词00": 500.0,
        }
    }
    runtime_decoder._phrase_prefix_index = {
        "abcdefghijklxy": [
            {
                "text": "超长词00",
                "entry_type": "phrase",
                "pinyin_tone": "chao1 chang2 ci2",
                "yime_code": "abcdefghijklxyzz",
                "sort_weight": 280.0,
                "text_length": 4,
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdefghijklxy")

    assert candidates == ["超长词00"]
    assert "[long-context-prefix-3]" in status
    assert "超长词00[prefix/C-continuous]" in status


def test_stage_d_prefers_continuous_context_priority_over_local_phrase_priority() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._local_phrase_priority_rules = {
        "abcdefgh": {
            "你号": 500.0,
        }
    }
    runtime_decoder._continuous_input_priority_rules = {
        "abcdefgh": {
            "你好": 900.0,
        }
    }
    runtime_decoder.by_code = {
        "abcdefgh": [
            {
                "text": "你号",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao4",
                "yime_code": "abcdefgh",
                "sort_weight": 320.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "你好",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3",
                "yime_code": "abcdefgh",
                "sort_weight": 280.0,
                "text_length": 2,
                "is_common": 1,
            },
        ]
    }
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text("abcdefgh")

    assert candidates[:2] == ["你好", "你号"]
    assert "你好[exact/D-continuous]" in status
    assert "你号[exact/D-local]" in status


def test_generated_continuous_rule_file_promotes_matching_prefix_candidate() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._continuous_input_priority_rules = _load_generated_continuous_rules()

    lookup_code, targets = next(iter(runtime_decoder._continuous_input_priority_rules.items()))
    target_text, _boost = next(iter(targets.items()))
    runtime_decoder._phrase_prefix_index = {
        lookup_code: [
            {
                "text": "占位词",
                "entry_type": "phrase",
                "pinyin_tone": "zhan4 wei4 ci2",
                "yime_code": lookup_code + "x",
                "sort_weight": 999.0,
                "text_length": 3,
                "is_common": 1,
            },
            {
                "text": target_text,
                "entry_type": "phrase",
                "pinyin_tone": "generated target",
                "yime_code": lookup_code + "y",
                "sort_weight": 100.0,
                "text_length": max(len(target_text), 2),
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text(lookup_code)

    assert candidates[:2] == [target_text, "占位词"]
    assert f"{target_text}[prefix/C-continuous]" in status


def test_generated_continuous_rule_file_excludes_filtered_noise_groups() -> None:
    generated_rules = _load_generated_continuous_rules()

    target_sets = {frozenset(targets) for targets in (set(rule_targets) for rule_targets in generated_rules.values())}

    assert frozenset({"及时", "即使"}) not in target_sets
    assert frozenset({"灵魂", "灵活"}) not in target_sets


def test_generated_continuous_rule_file_keeps_multi_target_groups_only_at_lengths_6_and_7() -> None:
    generated_rules = _load_generated_continuous_rules()

    multi_target_lookup_lengths = {
        len(lookup_code)
        for lookup_code, targets in generated_rules.items()
        if len(targets) > 1
    }

    assert multi_target_lookup_lengths == {6, 7}


def test_generated_variant_and_stem_rules_stay_on_first_page() -> None:
    retained_groups = [
        {"其他", "其它"},
        {"毕业", "毕业生"},
        {"机器", "机器人"},
        {"计算", "计算机"},
        {"验证", "验证集", "验证码"},
    ]

    for expected_targets in retained_groups:
        _assert_generated_rule_targets_stay_on_first_page(expected_targets)
