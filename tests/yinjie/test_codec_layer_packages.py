import unittest

from syllable.codec.input_shorthand import omit_middle_tone_if_same_quality_run
from syllable.codec.model_full_code import Yinjie as LayerYinjie
from syllable.codec.variable_length_yinyuan import (
    merge_adjacent_equal_yinyuan,
    to_variable_length_yinyuan_code,
    transform_full_code,
)
from syllable.codec.yinjie import Yinjie as LegacyYinjie


class TestCodecLayerPackages(unittest.TestCase):
    def test_model_full_code_exports_legacy_yinjie_type(self):
        self.assertIs(LayerYinjie, LegacyYinjie)

    def test_variable_length_yinyuan_merges_adjacent_duplicates(self):
        merged, merged_repeat_count = merge_adjacent_equal_yinyuan(["A", "B", "B", "C"])
        self.assertEqual(merged, ["A", "B", "C"])
        self.assertEqual(merged_repeat_count, 1)

    def test_variable_length_yinyuan_transforms_four_code(self):
        result = transform_full_code("ABBC")
        self.assertEqual(result.full_code, "ABBC")
        self.assertEqual(result.merged_code, "ABC")
        self.assertEqual(result.variable_code, "ABC")
        self.assertEqual(result.merged_adjacent_count, 1)

    def test_variable_length_merges_adjacent_equal_yinyuan_composing_ganyin(self):
        result = transform_full_code("XAAB")
        self.assertEqual(result.merged_code, "XAB")
        self.assertEqual(result.variable_code, "XAB")
        self.assertEqual(result.merged_adjacent_count, 1)
        self.assertFalse(result.omitted_virtual_initial)

    def test_variable_length_covers_four_three_yinyuan_ganyin_structures(self):
        cases = {
            "XABC": "XABC",  # 呼音、主音、末音三者不同
            "XAAC": "XAC",   # 只合并相同的呼音、主音
            "XABB": "XAB",   # 只合并相同的主音、末音
            "XAAA": "XA",    # 呼音、主音、末音三者合并
        }
        for full_code, variable_code in cases.items():
            with self.subTest(full_code=full_code):
                self.assertEqual(transform_full_code(full_code).variable_code, variable_code)

    def test_variable_length_yinyuan_never_merges_initial_with_ganyin(self):
        result = transform_full_code("AAAA")
        self.assertEqual(result.variable_code, "AA")
        self.assertEqual(result.merged_adjacent_count, 2)

    def test_variable_length_yinyuan_rejects_non_four_code(self):
        for code in ("", "ABC", "ABCDE"):
            with self.subTest(code=code):
                with self.assertRaises(ValueError):
                    transform_full_code(code)

    def test_variable_length_yinyuan_code_helper(self):
        self.assertEqual(to_variable_length_yinyuan_code("XAAA"), "XA")

    def test_input_shorthand_omits_middle_tone_for_same_quality_run(self):
        metadata = {
            "A": {"quality_group": 1, "tone_level": "high"},
            "B": {"quality_group": 1, "tone_level": "mid"},
            "C": {"quality_group": 1, "tone_level": "low"},
        }
        compressed, omitted = omit_middle_tone_if_same_quality_run(["A", "B", "C"], metadata)
        self.assertEqual(compressed, ["A", "C"])
        self.assertTrue(omitted)


if __name__ == "__main__":
    unittest.main()
