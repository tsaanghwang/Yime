from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_psc_rare_words_json import (
    clean_pdf_data_field,
    excel_column_label,
    parse_workbook_json,
    pinyin_characters_are_valid,
)


class RareWordImportTests(unittest.TestCase):
    def test_excel_column_labels(self) -> None:
        self.assertEqual(excel_column_label(2), "B")
        self.assertEqual(excel_column_label(27), "AA")

    def test_parse_cells_and_addresses(self) -> None:
        payload = {
            "Table 1": {
                "address": "B2:E3",
                "values": [["b", None, None, None], ["捌", " bā\n", "耙", "bà/pá"]],
            },
            "Table 2": {
                "address": "B2:C3",
                "values": [["零声母", None], ["螯", "áo"]],
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "values.json"
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            groups, entries, counts, _ = parse_workbook_json(path)
        self.assertEqual([group.group_label for group in groups], ["b", "零声母"])
        self.assertEqual(counts, [2, 1])
        self.assertEqual((entries[0].hanzi_cell, entries[0].pinyin_cell), ("B3", "C3"))
        self.assertEqual(entries[1].pinyin_nfc, "bà/pá")

    def test_pdf_watermark_and_pinyin_characters(self) -> None:
        pump = chr(0x6CF5)
        self.assertEqual(clean_pdf_data_field("P" + pump, True), (pump, True))
        self.assertEqual(clean_pdf_data_field("téngP", False), ("téng", True))
        self.assertTrue(pinyin_characters_are_valid("fāngxīng-wèi’ài"))
        self.assertTrue(pinyin_characters_are_valid("zhā·zǐ"))


if __name__ == "__main__":
    unittest.main()
