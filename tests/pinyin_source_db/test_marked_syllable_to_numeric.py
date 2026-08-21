import unittest

from yime.utils.marked_pinyin import (
    marked_pinyin_to_numeric as marked_phrase_to_numeric,
    marked_syllable_to_numeric,
)


class TestMarkedSyllableToNumeric(unittest.TestCase):
    def test_erhua_standalone_r_maps_to_er5(self):
        self.assertEqual(marked_syllable_to_numeric("r"), "er5")

    def test_erhua_r_does_not_affect_ri_syllables(self):
        self.assertEqual(marked_syllable_to_numeric("rì"), "ri4")
        self.assertEqual(marked_syllable_to_numeric("rī"), "ri1")

    def test_erhua_r_in_phrase_splits_to_er5(self):
        self.assertEqual(marked_phrase_to_numeric("nǐ r"), "ni3 er5")


if __name__ == "__main__":
    unittest.main()
