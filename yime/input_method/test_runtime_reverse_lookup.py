from pathlib import Path

from yime.input_method.utils.runtime_reverse_lookup import (
    RuntimeReverseLookup,
    looks_like_hanzi_text,
)


def test_looks_like_hanzi_text_detects_plain_hanzi() -> None:
    assert looks_like_hanzi_text("日本") is True
    assert looks_like_hanzi_text("ri4") is False


def test_runtime_reverse_lookup_returns_first_char_record() -> None:
    lookup = RuntimeReverseLookup(Path(__file__).resolve().parent.parent / "pinyin_hanzi.db")

    record = lookup.lookup_first("日")

    assert record is not None
    assert record.text == "日"
    assert record.numeric_pinyin == "ri4"
    assert record.marked_pinyin == "rì"
    assert record.yime_code


def test_runtime_reverse_lookup_returns_none_for_missing_phrase() -> None:
    lookup = RuntimeReverseLookup(Path(__file__).resolve().parent.parent / "pinyin_hanzi.db")

    assert lookup.lookup_first("今日") is None
