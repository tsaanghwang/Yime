import unittest

from yime.utils.numeric_pinyin_standardizer import standardize_numeric_pinyin


class TestNumericPinyinStandardizer(unittest.TestCase):
    def test_standardizes_l_n_v_series(self):
        cases = {
            "lv2": "lü2",
            "lv3": "lü3",
            "lv4": "lü4",
            "lve4": "lüe4",
            "lvan2": "lüan2",
            "lvan3": "lüan3",
            "nv2": "nü2",
            "nv3": "nü3",
            "nv4": "nü4",
            "nve4": "nüe4",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(standardize_numeric_pinyin(raw), expected)

    def test_keeps_non_v_spellings(self):
        self.assertEqual(standardize_numeric_pinyin("lüe4"), "lüe4")
        self.assertEqual(standardize_numeric_pinyin("zhi4"), "zhi4")


if __name__ == "__main__":
    unittest.main()
