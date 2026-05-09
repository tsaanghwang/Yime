from __future__ import annotations

from pathlib import Path

from yime.input_method.core.char_code_index import CharCodeIndex
from yime.input_method.core.decoders import RuntimeCandidateDecoder
from yime.input_method.core.runtime_ranking import load_local_phrase_priority_rules


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
        Path(__file__).resolve().parents[1] / "internal_data" / "continuous_input_priority_rules.json",
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


def test_generated_variant_and_stem_rules_stay_on_first_page() -> None:
    runtime_decoder = _build_runtime_decoder()
    generated_rules = _load_generated_continuous_rules()
    runtime_decoder._continuous_input_priority_rules = generated_rules

    lookup_code, _targets = _find_generated_rule_by_targets(
        generated_rules,
        {"其他", "其它"},
    )
    runtime_decoder._phrase_prefix_index = {
        lookup_code: [
            {
                "text": "占位词一",
                "entry_type": "phrase",
                "pinyin_tone": "zhan4 wei4 ci2 yi1",
                "yime_code": lookup_code + "a",
                "sort_weight": 999.0,
                "text_length": 4,
                "is_common": 1,
            },
            {
                "text": "占位词二",
                "entry_type": "phrase",
                "pinyin_tone": "zhan4 wei4 ci2 er4",
                "yime_code": lookup_code + "b",
                "sort_weight": 998.0,
                "text_length": 4,
                "is_common": 1,
            },
            {
                "text": "占位词三",
                "entry_type": "phrase",
                "pinyin_tone": "zhan4 wei4 ci2 san1",
                "yime_code": lookup_code + "c",
                "sort_weight": 997.0,
                "text_length": 4,
                "is_common": 1,
            },
            {
                "text": "其他",
                "entry_type": "phrase",
                "pinyin_tone": "qi2 ta1",
                "yime_code": lookup_code + "d",
                "sort_weight": 100.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "其它",
                "entry_type": "phrase",
                "pinyin_tone": "qi2 ta1",
                "yime_code": lookup_code + "e",
                "sort_weight": 90.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "占位词四",
                "entry_type": "phrase",
                "pinyin_tone": "zhan4 wei4 ci2 si4",
                "yime_code": lookup_code + "f",
                "sort_weight": 89.0,
                "text_length": 4,
                "is_common": 1,
            },
        ]
    }

    _canonical, _active, _pinyin, candidates, status = runtime_decoder.decode_text(lookup_code)

    assert candidates[:5] == ["其他", "其它", "占位词一", "占位词二", "占位词三"]
    assert "其他[prefix/C-continuous]" in status
    assert "其它[prefix/C-continuous]" in status
