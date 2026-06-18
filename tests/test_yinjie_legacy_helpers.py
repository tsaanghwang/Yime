# tests/test_yinjie_legacy_helpers.py
"""Yinjie 主链与 legacy 宽松切分 / 草稿简拼的兼容行为测试。"""

import unittest

from syllable.codec.yinjie import Yinjie
from syllable.codec.yinjie_jianpin_draft import simplify_ganyin_repeats, simplify_loose_structure
from syllable.codec.yinjie_loose_split import from_legacy_pinyin_chars, split_loose_encoded_string


class TestYinjieStructure(unittest.TestCase):
    def test_init_with_all_parameters(self):
        syllable = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        self.assertEqual(syllable.initial, "zh")
        self.assertEqual(syllable.ascender, "o")
        self.assertEqual(syllable.peak, "n")
        self.assertEqual(syllable.descender, "g")

    def test_init_with_partial_parameters(self):
        syllable = Yinjie(initial="zh", peak="a")
        self.assertEqual(syllable.initial, "zh")
        self.assertIsNone(syllable.ascender)
        self.assertEqual(syllable.peak, "a")
        self.assertIsNone(syllable.descender)

    def test_init_with_no_parameters(self):
        syllable = Yinjie()
        self.assertIsNone(syllable.initial)
        self.assertIsNone(syllable.ascender)
        self.assertIsNone(syllable.peak)
        self.assertIsNone(syllable.descender)

    def test_ganyin_code_full(self):
        syllable = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        self.assertEqual(syllable.ganyin_code, "ong")

    def test_ganyin_code_partial(self):
        syllable = Yinjie(ascender="a", peak="i")
        self.assertEqual(syllable.ganyin_code, "ai")

    def test_ganyin_code_empty(self):
        syllable = Yinjie(initial="zh")
        self.assertEqual(syllable.ganyin_code, "")

    def test_rime_property(self):
        syllable = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        rime = syllable.rime
        self.assertEqual(rime["peak"], "n")
        self.assertEqual(rime["descender"], "g")

    def test_rime_property_empty(self):
        syllable = Yinjie(initial="zh", ascender="a")
        rime = syllable.rime
        self.assertIsNone(rime["peak"])
        self.assertIsNone(rime["descender"])

    def test_classify_codes_full(self):
        syllable = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, ["zh"])
        self.assertEqual(musical, ["o", "n", "g"])

    def test_classify_codes_partial(self):
        syllable = Yinjie(initial="zh", peak="a")
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, ["zh"])
        self.assertEqual(musical, ["a"])

    def test_classify_codes_empty(self):
        syllable = Yinjie()
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, [])
        self.assertEqual(musical, [])

    def test_syllable_reconstruction(self):
        syllable = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        full_syllable = (syllable.initial or "") + syllable.ganyin_code
        self.assertEqual(full_syllable, "zhong")

    def test_syllable_equality(self):
        syllable1 = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        syllable2 = Yinjie(initial="zh", ascender="o", peak="n", descender="g")
        self.assertEqual(syllable1.initial, syllable2.initial)
        self.assertEqual(syllable1.ascender, syllable2.ascender)
        self.assertEqual(syllable1.peak, syllable2.peak)
        self.assertEqual(syllable1.descender, syllable2.descender)

    def test_multiple_syllables(self):
        syllables = [
            Yinjie(initial="zh", ascender="o", peak="n", descender="g"),
            Yinjie(initial="g", ascender="u", peak="o"),
            Yinjie(initial="r", ascender="e", peak="n"),
        ]
        self.assertEqual(syllables[0].ganyin_code, "ong")
        self.assertEqual(syllables[1].ganyin_code, "uo")
        self.assertEqual(syllables[2].ganyin_code, "en")

    def test_syllable_modification(self):
        syllable = Yinjie(initial="zh", peak="a")
        self.assertEqual(syllable.ganyin_code, "a")
        syllable.ascender = "i"
        self.assertEqual(syllable.ganyin_code, "ia")
        syllable.descender = "ng"
        self.assertEqual(syllable.ganyin_code, "iang")


class TestLooseEncodedSplit(unittest.TestCase):
    def test_split_loose_legacy_pinyin_like_string(self):
        result = split_loose_encoded_string("zhong")
        self.assertIsInstance(result, Yinjie)
        self.assertEqual(result.initial, "z")
        self.assertEqual(result.descender, "ng")

    def test_split_loose_short(self):
        result = split_loose_encoded_string("a")
        self.assertEqual(result.initial, "a")
        self.assertIsNone(result.ascender)

    def test_split_loose_empty_raises(self):
        with self.assertRaises(ValueError):
            split_loose_encoded_string("")

    def test_split_loose_various_lengths(self):
        for case in ("a", "ab", "abc", "abcd", "abcde"):
            result = split_loose_encoded_string(case)
            self.assertIsInstance(result, Yinjie)

    def test_from_legacy_pinyin_chars(self):
        syllable = from_legacy_pinyin_chars("zhong")
        self.assertEqual(syllable.initial, "z")
        self.assertEqual(syllable.ascender, "h")
        self.assertEqual(syllable.peak, "o")
        self.assertEqual(syllable.descender, "n")


class TestJianpinDraft(unittest.TestCase):
    def test_simplify_ganyin_repeats(self):
        self.assertEqual(simplify_ganyin_repeats("ABBC"), "ABC")

    def test_simplify_loose_structure(self):
        yinjie = Yinjie(initial="A", ascender="B", peak="B", descender="C")
        simplified = simplify_loose_structure(yinjie)
        self.assertEqual(simplified.get_full_code(), "ABC")


if __name__ == "__main__":
    unittest.main()
