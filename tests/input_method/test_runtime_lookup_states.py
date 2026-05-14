from __future__ import annotations

from yime.input_method.core.char_code_index import CharCodeIndex
from yime.input_method.core.decoders import RuntimeCandidateDecoder
from yime.input_method.core.runtime_lookup import build_runtime_lookup_plan


def _build_runtime_decoder() -> RuntimeCandidateDecoder:
    runtime_decoder = RuntimeCandidateDecoder.__new__(RuntimeCandidateDecoder)
    runtime_decoder.bmp_to_canonical = {}
    runtime_decoder.numeric_to_marked_pinyin = {}
    runtime_decoder._user_freq_by_candidate = {}
    runtime_decoder._local_phrase_priority_rules = {}
    runtime_decoder._continuous_input_priority_rules = {}
    runtime_decoder.by_code = {}
    runtime_decoder._char_sort_weight_by_text = {}
    runtime_decoder._phrase_prefix_index = {}
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)
    return runtime_decoder


def test_build_runtime_lookup_plan_marks_continuous_input_states() -> None:
    plan_a = build_runtime_lookup_plan("abc")
    assert plan_a.stage == "A"
    assert plan_a.phrase_prefix_pool == ""
    assert plan_a.phrase_prefix_limit == 0

    plan_b = build_runtime_lookup_plan("abcd")
    assert plan_b.stage == "B"
    assert plan_b.phrase_prefix_pool == "recent-syllable-prefix"
    assert plan_b.phrase_prefix_limit == 64

    plan_c = build_runtime_lookup_plan("abcdxy")
    assert plan_c.stage == "C"
    assert plan_c.lookup_code == "abcd"
    assert plan_c.context_code == "abcdxy"
    assert plan_c.phrase_prefix_pool == "long-context-prefix-1"
    assert plan_c.phrase_prefix_limit == 32

    plan_c2 = build_runtime_lookup_plan("abcdefghxy")
    assert plan_c2.stage == "C"
    assert plan_c2.lookup_code == "efgh"
    assert plan_c2.context_code == "abcdefghxy"
    assert plan_c2.phrase_prefix_pool == "long-context-prefix-2"
    assert plan_c2.phrase_prefix_limit == 24

    plan_c3 = build_runtime_lookup_plan("abcdefghijklxy")
    assert plan_c3.stage == "C"
    assert plan_c3.lookup_code == "ijkl"
    assert plan_c3.context_code == "abcdefghijklxy"
    assert plan_c3.phrase_prefix_pool == "long-context-prefix-3"
    assert plan_c3.phrase_prefix_limit == 16

    plan_d = build_runtime_lookup_plan("abcdefgh")
    assert plan_d.stage == "D"
    assert plan_d.lookup_code == "abcdefgh"
    assert plan_d.phrase_prefix_pool == ""
    assert plan_d.phrase_prefix_limit == 0


def test_continuous_input_prefers_context_prefix_before_single_syllable_bucket() -> None:
    runtime_decoder = _build_runtime_decoder()
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
        "abcdxy": [
            {
                "text": "你好啊",
                "entry_type": "phrase",
                "pinyin_tone": "ni3 hao3 a5",
                "yime_code": "abcdxywv",
                "sort_weight": 280.0,
                "text_length": 3,
                "is_common": 1,
            }
        ]
    }
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)

    _canonical, _active, _pinyin, candidates, _status = runtime_decoder.decode_text("abcdxy")

    assert candidates == ["你好啊"]


def test_phrase_prefix_pool_limits_differ_between_recent_and_long_context() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._phrase_prefix_index = {
        "abcd": [
            {
                "text": f"词{index:02d}",
                "entry_type": "phrase",
                "pinyin_tone": f"ci2 {index}",
                "yime_code": f"abcd{index:04d}",
                "sort_weight": float(1000 - index),
                "text_length": 2,
                "is_common": 1,
            }
            for index in range(70)
        ],
        "abcdxy": [
            {
                "text": f"长词{index:02d}",
                "entry_type": "phrase",
                "pinyin_tone": f"chang2 ci2 {index}",
                "yime_code": f"abcdxy{index:04d}",
                "sort_weight": float(1000 - index),
                "text_length": 3,
                "is_common": 1,
            }
            for index in range(40)
        ],
        "abcdefghxy": [
            {
                "text": f"中长词{index:02d}",
                "entry_type": "phrase",
                "pinyin_tone": f"zhong1 chang2 ci2 {index}",
                "yime_code": f"abcdefghxy{index:04d}",
                "sort_weight": float(1000 - index),
                "text_length": 3,
                "is_common": 1,
            }
            for index in range(40)
        ],
        "abcdefghijklxy": [
            {
                "text": f"超长词{index:02d}",
                "entry_type": "phrase",
                "pinyin_tone": f"chao1 chang2 ci2 {index}",
                "yime_code": f"abcdefghijklxy{index:04d}",
                "sort_weight": float(1000 - index),
                "text_length": 4,
                "is_common": 1,
            }
            for index in range(40)
        ],
    }

    _canonical_b, _active_b, _pinyin_b, candidates_b, _status_b = runtime_decoder.decode_text("abcd")
    _canonical_c1, _active_c1, _pinyin_c1, candidates_c1, _status_c1 = runtime_decoder.decode_text("abcdxy")
    _canonical_c2, _active_c2, _pinyin_c2, candidates_c2, _status_c2 = runtime_decoder.decode_text("abcdefghxy")
    _canonical_c3, _active_c3, _pinyin_c3, candidates_c3, _status_c3 = runtime_decoder.decode_text("abcdefghijklxy")

    assert len(candidates_b) == 64
    assert candidates_b[0] == "词00"
    assert candidates_b[-1] == "词63"
    assert len(candidates_c1) == 32
    assert candidates_c1[0] == "长词00"
    assert candidates_c1[-1] == "长词31"
    assert len(candidates_c2) == 24
    assert candidates_c2[0] == "中长词00"
    assert candidates_c2[-1] == "中长词23"
    assert len(candidates_c3) == 16
    assert candidates_c3[0] == "超长词00"
    assert candidates_c3[-1] == "超长词15"


def test_stage_b_keeps_a_rare_char_representative_on_second_page_for_dense_exact_bucket() -> None:
    runtime_decoder = _build_runtime_decoder()
    runtime_decoder._phrase_prefix_index = {
        "abcd": [
            {
                "text": f"词{index:02d}",
                "entry_type": "phrase",
                "pinyin_tone": f"ci2 {index}",
                "yime_code": f"abcd{index:04d}",
                "sort_weight": float(1000 - index),
                "text_length": 2,
                "is_common": 1,
            }
            for index in range(5)
        ]
    }
    runtime_decoder.by_code = {
        "abcd": [
            {
                "text": chr(0x4E00 + index),
                "entry_type": "char",
                "pinyin_tone": f"zi4 {index}",
                "yime_code": "abcd",
                "sort_weight": float(500 - index),
                "text_length": 1,
                "is_common": 1,
                "usage_tier": "common_high",
            }
            for index in range(70)
        ]
        + [
            {
                "text": "龘",
                "entry_type": "char",
                "pinyin_tone": "da2",
                "yime_code": "abcd",
                "sort_weight": 1.0,
                "text_length": 1,
                "is_common": 0,
                "usage_tier": "rare",
            }
        ]
    }
    runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)

    _canonical, _active, _pinyin, candidates, _status = runtime_decoder.decode_text("abcd")

    assert candidates[:5] == ["词00", "词01", "词02", "词03", "词04"]
    assert candidates[6] == "龘"
