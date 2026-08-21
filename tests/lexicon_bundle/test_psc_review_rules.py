from __future__ import annotations

from dataclasses import replace

from yime.lexicon_bundle.psc_audit import ReviewCase, normalize_marked_pinyin
from yime.lexicon_bundle.psc_review_rules import suggest_review_case


def _case(
    text: str,
    pinyin: str,
    canonical_marked: str,
    canonical_numeric: str,
    *,
    source_index: int = 1,
    lane: str = "canonical_pronunciation_review",
) -> ReviewCase:
    return ReviewCase(
        case_key=f"case:{text}:{pinyin}",
        review_lane=lane,
        review_priority=100,
        text=text,
        pinyin_forms=(pinyin,),
        pinyin_variants=(normalize_marked_pinyin(pinyin),),
        outcomes=("pronunciation_conflict",),
        evidence_sources=("psc_main",),
        evidence_count=1,
        canonical_readings=(
            {
                "marked": canonical_marked,
                "numeric": canonical_numeric,
                "is_primary": True,
                "reading_rank": 1,
                "sources": "fixture",
                "neutral_tone_status": "none",
            },
        ),
        accepted_readings=(),
        unmatched_variants=(normalize_marked_pinyin(pinyin),),
        evidence_items=(
            {
                "source_kind": "psc_main",
                "locator": {"source_index": source_index},
            },
        ),
        explanation="fixture",
        decision="pending",
        selected_pinyin="",
        note="",
        reviewer="",
        updated_at_utc="",
    )


def test_source_index_prefix_rule_requires_matching_locator_suffix() -> None:
    suggestion = suggest_review_case(
        _case("一心", "0 yīxīn", "yí xīn", "yi2 xin1", source_index=7160)
    )
    assert suggestion is not None
    assert suggestion.rule_id == "ocr_source_index_prefix"
    assert suggestion.decision == "psc_evidence_error"
    assert suggestion.selected_pinyin == "yīxīn"
    assert "序号末位“0”" in suggestion.note

    manual = suggest_review_case(
        _case("一心", "0 yīxīn", "yí xīn", "yi2 xin1", source_index=7161)
    )
    assert manual is not None
    assert manual.rule_id == "ocr_source_index_prefix_manual"
    assert not manual.batch_safe

    manual = suggest_review_case(
        _case("以及", "8 yijí", "yǐ jí", "yi3 ji2", source_index=7188)
    )
    assert manual is not None
    assert manual.rule_id == "ocr_source_index_prefix_manual"

    punctuated = suggest_review_case(
        _case("以及", "8，yǐjí", "yǐ jí", "yi3 ji2", source_index=7188)
    )
    assert punctuated is not None
    assert punctuated.rule_id == "ocr_source_index_prefix"
    assert punctuated.batch_safe


def test_yi_sandhi_rule_only_changes_aligned_yi_tone() -> None:
    examples = (
        ("一定", "yīdìng", "yí dìng", "yi2 ding4"),
        ("一如既往", "yīrú-jìwǎng", "yì rú jì wǎng", "yi4 ru2 ji4 wang3"),
    )
    for text, psc, marked, numeric in examples:
        suggestion = suggest_review_case(_case(text, psc, marked, numeric))
        assert suggestion is not None
        assert suggestion.rule_id == "yi_sandhi_underlying"
        assert suggestion.decision == "accept_psc"
        assert suggestion.selected_pinyin == psc
        assert "语流变调" in suggestion.note

    assert suggest_review_case(
        _case("一定", "yīdān", "yí dìng", "yi2 ding4")
    ) is None


def test_bu_sandhi_rule_is_equally_position_preserving() -> None:
    suggestion = suggest_review_case(_case("不要", "bùyào", "bú yào", "bu2 yao4"))
    assert suggestion is not None
    assert suggestion.rule_id == "bu_sandhi_underlying"
    assert suggestion.decision == "accept_psc"
    assert suggestion.selected_pinyin == "bùyào"


def test_missing_tone_mark_is_grouped_but_not_batch_decided() -> None:
    suggestion = suggest_review_case(
        _case(
            "一技之长",
            "yījizhīcháng",
            "yí jì zhī cháng",
            "yi2 ji4 zhi1 chang2",
        )
    )
    assert suggestion is not None
    assert suggestion.rule_id == "ocr_missing_tone_mark"
    assert suggestion.rule_label == "调号变成了点"
    assert suggestion.decision == "psc_evidence_error"
    assert suggestion.selected_pinyin == "yī jì zhī cháng"
    assert not suggestion.batch_safe


def test_neutral_primary_keeps_lexically_distinct_full_tone_reading() -> None:
    primary = _case("上头", "shàngtóu", "shàng tou", "shang4 tou5")
    alternate = {
        **primary.canonical_readings[0],
        "marked": "shàng tóu",
        "numeric": "shang4 tou2",
        "is_primary": False,
        "reading_rank": 2,
    }
    strict = suggest_review_case(
        replace(primary, canonical_readings=(*primary.canonical_readings, alternate))
    )
    assert strict is not None
    assert strict.rule_id == "neutral_primary_semantic_review"
    assert strict.rule_label == "轻声与本调分义（两读并存）"
    assert strict.decision == "keep_both"
    assert strict.selected_pinyin == "shàngtóu"
    assert strict.batch_safe

    reference = suggest_review_case(
        replace(
            primary,
            review_lane="contextual_reference_review",
            canonical_readings=(*primary.canonical_readings, alternate),
        )
    )
    assert reference is not None
    assert reference.rule_id == "neutral_primary_reference"
    assert reference.decision == "defer"
    assert not reference.batch_safe

    complex_case = suggest_review_case(primary)
    assert complex_case is not None
    assert complex_case.rule_id == "neutral_primary_complex"
    assert complex_case.decision == "defer"
    assert not complex_case.batch_safe


def test_policy_lane_without_strict_data_rule_is_not_auto_decided() -> None:
    assert suggest_review_case(
        _case(
            "花儿",
            "huār",
            "huā ér",
            "hua1 er2",
            lane="erhua_policy_review",
        )
    ) is None
