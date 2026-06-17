import unittest

from syllable.analysis.syllable_splitter import SyllableSplitter


def parse_numeric_tone_pinyin(pinyin_str: str) -> dict:
    """Parse numeric-tone pinyin into initial, final, and tone (same rules as legacy importer)."""
    shouyin, ganyin = SyllableSplitter.split_syllable(pinyin_str)
    normalized_initial = "" if shouyin == "'" else shouyin

    numeric_final = SyllableSplitter.REVERSE_SPECIAL_SYLLABLES.get(ganyin, ganyin)
    tone = int(numeric_final[-1]) if numeric_final and numeric_final[-1].isdigit() else 1
    yunmu = numeric_final[:-1] if numeric_final and numeric_final[-1].isdigit() else numeric_final

    return {
        "声母": normalized_initial,
        "韵母": yunmu,
        "声调": tone,
    }


class TestSplitNumericPinyin(unittest.TestCase):
    def test_parse_uses_splitter_rule_for_abbreviated_finals(self):
        self.assertEqual(
            parse_numeric_tone_pinyin("jiu2"),
            {"声母": "j", "韵母": "iou", "声调": 2},
        )

    def test_parse_uses_splitter_rule_for_y_family(self):
        self.assertEqual(
            parse_numeric_tone_pinyin("yue4"),
            {"声母": "ɥ", "韵母": "üe", "声调": 4},
        )

    def test_parse_uses_splitter_rule_for_apical_vowel(self):
        self.assertEqual(
            parse_numeric_tone_pinyin("zhi4"),
            {"声母": "zh", "韵母": "_i", "声调": 4},
        )

    def test_parse_uses_splitter_rule_for_zero_initial(self):
        self.assertEqual(
            parse_numeric_tone_pinyin("a1"),
            {"声母": "", "韵母": "a", "声调": 1},
        )

    def test_parse_handles_special_syllables(self):
        self.assertEqual(
            parse_numeric_tone_pinyin("m2"),
            {"声母": "", "韵母": "m", "声调": 2},
        )


if __name__ == "__main__":
    unittest.main()
