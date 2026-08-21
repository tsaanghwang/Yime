from yime.utils.numeric_pinyin_code import (
    normalize_numeric_pinyin_syllable_spacing,
    resolve_canonical_code_from_numeric_pinyin,
)


def test_compact_numeric_pinyin_is_split_only_at_tone_digits() -> None:
    assert normalize_numeric_pinyin_syllable_spacing("ni3hao3") == "ni3 hao3"
    assert normalize_numeric_pinyin_syllable_spacing("lü4 se4") == "lü4 se4"


def test_missing_syllable_code_fails_closed() -> None:
    mapping = {"ni3": "ABCD", "hao3": "EFGH"}
    assert resolve_canonical_code_from_numeric_pinyin(mapping, "ni3hao3") == "ABCDEFGH"
    assert resolve_canonical_code_from_numeric_pinyin(mapping, "ni3 ma5") == ""
