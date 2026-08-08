from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_psc_neutral_tone_pdf import (
    normalize_hanzi,
    normalize_pinyin,
    pinyin_characters_are_valid,
    strip_watermark_lines,
)


class NeutralToneImportTests(unittest.TestCase):
    def test_watermark_fragment_is_removed_without_losing_cell_text(self) -> None:
        self.assertEqual(strip_watermark_lines("畅\ncāngying"), "cāngying")
        self.assertEqual(strip_watermark_lines("P\n豹子"), "豹子")
        self.assertEqual(strip_watermark_lines("A\ndāying"), "dāying")

    def test_hanzi_and_pinyin_normalization(self) -> None:
        self.assertEqual(normalize_hanzi("普\n除了"), "除了")
        raw, normalized = normalize_pinyin("zhǐtou（zhí tou）")
        self.assertEqual(raw, "zhǐtou（zhí tou）")
        self.assertEqual(normalized, "zhǐtou(zhítou)")

    def test_pinyin_character_gate(self) -> None:
        self.assertTrue(pinyin_characters_are_valid("nǚxu"))
        self.assertTrue(pinyin_characters_are_valid("zhǐjia(zhījia)"))
        self.assertFalse(pinyin_characters_are_valid("bāzi1"))


if __name__ == "__main__":
    unittest.main()
