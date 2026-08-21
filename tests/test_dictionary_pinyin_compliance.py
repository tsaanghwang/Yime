from __future__ import annotations

from yime.utils.dictionary_pinyin_compliance import canonicalize_reading, review_syllable
from yime.utils.marked_pinyin import marked_syllable_to_numeric


def test_marked_converter_preserves_special_e_quality() -> None:
    assert marked_syllable_to_numeric("ê̄") == "ê1"
    assert marked_syllable_to_numeric("ế") == "ê2"
    assert marked_syllable_to_numeric("ê̌") == "ê3"
    assert marked_syllable_to_numeric("ề") == "ê4"


def test_reviewed_source_record_is_corrected_before_decoding() -> None:
    review = review_syllable("wòng", codepoint="U+25948")
    assert review.status == "source_correction"
    assert review.source_numeric == "wong4"
    assert review.canonical_numeric == "weng4"
    assert review.canonical_marked == "wèng"

    second = review_syllable("wòng", codepoint="U+259B7")
    assert second.status == "source_correction"
    assert second.canonical_numeric == "weng4"


def test_wong_is_not_a_general_alias() -> None:
    review = review_syllable("wòng")
    assert not review.accepted
    assert review.rule_id == "SRC-UNADMITTED-ORTHOGRAPHY"


def test_bong_source_record_is_preserved_but_excluded_from_decoding() -> None:
    review = review_syllable("bòng", codepoint="U+31FC5")
    assert not review.accepted
    assert review.known_exclusion
    assert review.status == "excluded_nonstandard_orthography"


def test_bong_is_not_admitted_as_an_ordinary_pinyin_syllable() -> None:
    review = review_syllable("bòng")
    assert not review.accepted
    assert review.rule_id == "SRC-UNADMITTED-ORTHOGRAPHY"


def test_obsolete_lan_reduction_is_excluded_for_simplified_and_traditional() -> None:
    for codepoint, rule_id in (
        ("U+84DD", "SRC-EXCLUDE-U84DD-LA5"),
        ("U+85CD", "SRC-EXCLUDE-U85CD-LA5"),
    ):
        obsolete = review_syllable("la", codepoint=codepoint)
        assert not obsolete.accepted
        assert obsolete.known_exclusion
        assert obsolete.status == "excluded_obsolete_reading"
        assert obsolete.rule_id == rule_id

    assert review_syllable("la").accepted
    assert review_syllable("lán", codepoint="U+84DD").accepted
    assert review_syllable("lán", codepoint="U+85CD").accepted


def test_technical_v_spelling_is_rejected_at_dictionary_boundary() -> None:
    review = review_syllable("lv4")
    assert not review.accepted
    assert review.rule_id == "SRC-TECHNICAL-PINYIN"


def test_uppercase_source_spelling_is_rejected_instead_of_silently_lowered() -> None:
    review = review_syllable("Wèng")
    assert not review.accepted
    assert review.rule_id == "SRC-INVALID-CHARACTER"


def test_unreviewed_but_well_shaped_spelling_is_rejected() -> None:
    assert review_syllable("abc").rule_id == "SRC-UNADMITTED-ORTHOGRAPHY"
    assert review_syllable("fiōng").rule_id == "SRC-UNADMITTED-ORTHOGRAPHY"


def test_erhua_suffix_r_restores_full_numeric_er_form() -> None:
    canonical, reviews = canonicalize_reading("r dòng")
    assert canonical == "er dòng"
    assert reviews[0].canonical_marked == "er"
    assert [item.canonical_numeric for item in reviews] == ["er5", "dong4"]
