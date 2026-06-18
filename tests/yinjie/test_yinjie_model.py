"""Yinjie 结构模型术语与编解码字段一致性。"""

import unittest

from syllable.codec.yinjie import GanyinSlots, Yinjie, YunyinSlots


class TestYinjieTerminologySlots(unittest.TestCase):
    def setUp(self):
        self.yinjie = Yinjie(initial="N", ascender="A", peak="B", descender="C")

    def test_legacy_fields_unchanged(self):
        self.assertEqual(self.yinjie.initial, "N")
        self.assertEqual(self.yinjie.ascender, "A")
        self.assertEqual(self.yinjie.peak, "B")
        self.assertEqual(self.yinjie.descender, "C")

    def test_terminology_aliases(self):
        self.assertEqual(self.yinjie.shouyin, "N")
        self.assertEqual(self.yinjie.huyin, "A")
        self.assertEqual(self.yinjie.zhuyin, "B")
        self.assertEqual(self.yinjie.moyin, "C")

    def test_recursive_ganyin_structure(self):
        ganyin = self.yinjie.ganyin
        self.assertIsInstance(ganyin, GanyinSlots)
        self.assertEqual(ganyin.huyin, "A")
        self.assertIsInstance(ganyin.yunyin, YunyinSlots)
        self.assertEqual(ganyin.yunyin.zhuyin, "B")
        self.assertEqual(ganyin.yunyin.moyin, "C")

    def test_rime_compat_dict(self):
        self.assertEqual(
            self.yinjie.rime,
            {"zhuyin": "B", "moyin": "C", "peak": "B", "descender": "C"},
        )

    def test_from_code_and_to_code_roundtrip(self):
        code = "NABC"
        yinjie = Yinjie.from_code(code)
        self.assertEqual(yinjie.to_code(), code)
        self.assertEqual(yinjie.shouyin, "N")
        self.assertEqual(yinjie.huyin, "A")

    def test_ganyin_code_string_concat(self):
        self.assertEqual(self.yinjie.ganyin_code, "ABC")

    def test_classify_phonemes(self):
        noise, musical = self.yinjie.classify_phonemes()
        self.assertEqual(noise, ["N"])
        self.assertEqual(musical, ["A", "B", "C"])

    def test_merge_duplicate_phonemes(self):
        merged = Yinjie(initial="N", ascender="A", peak="A", descender="C").merge_duplicate_phonemes()
        self.assertEqual(merged.to_code(), "NAC")


if __name__ == "__main__":
    unittest.main()
