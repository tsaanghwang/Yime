from __future__ import annotations

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_psc_passage_pronunciations import (
    draft_pdf_word_items,
    group_pdf_words,
    latin_start_index,
    normalize_passage_pinyin,
    split_marked_text,
    split_term_pinyin,
)


class PassagePronunciationImportTests(unittest.TestCase):
    def test_split_multiple_items_without_spaces(self) -> None:
        self.assertEqual(
            split_marked_text("13.认为rènwéi14.为了wèile"),
            [(13, "认为rènwéi"), (14, "为了wèile")],
        )

    def test_split_term_and_pinyin(self) -> None:
        self.assertEqual(split_term_pinyin("规矩guīju"), ("规矩", "guīju", "guīju"))
        self.assertEqual(
            split_term_pinyin("琵琶pí · pá"),
            ("琵琶", "pí · pá", "pí·pá"),
        )
        self.assertEqual(split_term_pinyin("对峙"), ("对峙", "", ""))

    def test_latin_start_and_normalization(self) -> None:
        self.assertEqual(latin_start_index("〇líng"), 1)
        self.assertEqual(normalize_passage_pinyin(" YĪN · WÈI "), ("YĪN · WÈI", "yīn·wèi"))

    def test_group_words_allows_small_baseline_drift(self) -> None:
        words = [
            {"text": "12.陡坡", "top": 10.9, "x0": 20},
            {"text": "dǒupō", "top": 10.0, "x0": 30},
            {"text": "13.便于biànyú", "top": 14.0, "x0": 20},
        ]
        rows = group_pdf_words(words)
        self.assertEqual([[word["text"] for word in row] for row in rows], [
            ["12.陡坡", "dǒupō"], ["13.便于biànyú"],
        ])

    def test_wrapped_pinyin_attaches_to_same_column(self) -> None:
        words = [
            {"text": "8.盏zhǎn", "top": 10.0, "x0": 100.0},
            {"text": "15.软绵绵", "top": 10.0, "x0": 200.0},
            {"text": "9.围绕wéirào", "top": 30.0, "x0": 100.0},
            {"text": "ruǎnmiánmián/ruǎnmiānmiān", "top": 30.0, "x0": 200.0},
        ]
        drafts = draft_pdf_word_items(words)
        item15 = next(item for item in drafts if item["source_item_no"] == 15)
        self.assertEqual(item15["payload"], "软绵绵 ruǎnmiánmián/ruǎnmiānmiān")

    def test_marker_only_word_accepts_following_term_and_pinyin(self) -> None:
        drafts = draft_pdf_word_items([
            {"text": "1.", "top": 10.9, "x0": 20.0},
            {"text": "酝酿yùnniàng", "top": 10.0, "x0": 30.0},
        ])
        self.assertEqual(drafts[0]["payload"], " 酝酿yùnniàng")


if __name__ == "__main__":
    unittest.main()
