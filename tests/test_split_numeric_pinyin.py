import unittest

from yime.utils.legacy_pinyin_tables.split_numeric_pinyin import 数字标调拼音导入器


class TestSplitNumericPinyin(unittest.TestCase):
    def setUp(self):
        self.importer = 数字标调拼音导入器()

    def test_parse_uses_splitter_rule_for_abbreviated_finals(self):
        self.assertEqual(
            self.importer.解析拼音("jiu2"),
            {"声母": "j", "韵母": "iou", "声调": 2},
        )

    def test_parse_uses_splitter_rule_for_y_family(self):
        self.assertEqual(
            self.importer.解析拼音("yue4"),
            {"声母": "ɥ", "韵母": "üe", "声调": 4},
        )

    def test_parse_uses_splitter_rule_for_apical_vowel(self):
        self.assertEqual(
            self.importer.解析拼音("zhi4"),
            {"声母": "zh", "韵母": "_i", "声调": 4},
        )

    def test_parse_uses_splitter_rule_for_zero_initial(self):
        self.assertEqual(
            self.importer.解析拼音("a1"),
            {"声母": "", "韵母": "a", "声调": 1},
        )

    def test_parse_handles_special_syllables(self):
        self.assertEqual(
            self.importer.解析拼音("m2"),
            {"声母": "", "韵母": "m", "声调": 2},
        )


if __name__ == "__main__":
    unittest.main()
