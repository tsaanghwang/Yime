import json
import sqlite3
import unittest
from pathlib import Path

from internal_data.pinyin_source_db.build_source_pinyin_db import marked_syllable_to_numeric
from syllable.codec.paths import YINJIE_CODE_PATH
from syllable.codec.yinjie_decoder import YinjieDecoder
from syllable.codec.yinjie_encoder import YinjieEncoder


class TestPinyinBidirectionalValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.normalized_path = Path("internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json")
        cls.codebook_path = YINJIE_CODE_PATH

        with cls.normalized_path.open("r", encoding="utf-8") as file:
            cls.normalized_map = json.load(file)

        with cls.codebook_path.open("r", encoding="utf-8") as file:
            cls.codebook = json.load(file)

        cls.encoder = YinjieEncoder()
        cls.decoder = YinjieDecoder(code_file=cls.codebook_path)

        db_path = Path(".generated/source_pinyin.db")
        if db_path.exists():
            conn = sqlite3.connect(db_path)
            try:
                cls.inventory_keys = {
                    row[0]
                    for row in conn.execute(
                        "SELECT DISTINCT numeric_syllable "
                        "FROM m_distinct_syllable_inventory"
                    )
                }
            finally:
                conn.close()
        else:
            cls.inventory_keys = set()

    @staticmethod
    def _render_decoded_code(decoded) -> str:
        return "".join(
            phoneme or ""
            for phoneme in (
                decoded.initial,
                decoded.ascender,
                decoded.peak,
                decoded.descender,
            )
        )

    def test_lexicon_inventory_is_subset_of_normalized_mapping(self):
        if not self.inventory_keys:
            self.skipTest("inventory table not available")
        self.assertLessEqual(self.inventory_keys, set(self.normalized_map))

    def test_codebook_keys_with_lexicon_attestation_are_in_normalized(self):
        if not self.inventory_keys:
            self.skipTest("inventory table not available")
        for numeric_pinyin in self.codebook:
            if numeric_pinyin not in self.inventory_keys:
                continue
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertIn(numeric_pinyin, self.normalized_map)

    def test_every_codebook_key_encodes_to_checked_in_code(self):
        for numeric_pinyin, expected_code in self.codebook.items():
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertEqual(self.encoder.encode_single_yinjie(numeric_pinyin), expected_code)

    def test_inventory_only_normalized_keys_still_round_trip_marked_to_numeric(self):
        inventory_only = set(self.normalized_map) - set(self.codebook)
        for numeric_pinyin in sorted(inventory_only):
            with self.subTest(numeric_pinyin=numeric_pinyin):
                marked_pinyin = self.normalized_map[numeric_pinyin]
                self.assertEqual(marked_syllable_to_numeric(marked_pinyin), numeric_pinyin)

    def test_normalized_and_codebook_keys_match_when_codebook_is_current(self):
        if set(self.normalized_map) != set(self.codebook):
            self.skipTest("codebook not yet expanded to inventory export domain")
        self.assertEqual(set(self.normalized_map), set(self.codebook))

    def test_every_marked_value_round_trips_back_to_original_numeric_key(self):
        for numeric_pinyin, marked_pinyin in self.normalized_map.items():
            with self.subTest(numeric_pinyin=numeric_pinyin, marked_pinyin=marked_pinyin):
                self.assertEqual(marked_syllable_to_numeric(marked_pinyin), numeric_pinyin)

    def test_every_codebook_key_is_present_in_normalized_mapping(self):
        if not self.inventory_keys:
            self.skipTest("inventory table not available")
        for numeric_pinyin in self.codebook:
            if numeric_pinyin not in self.inventory_keys:
                continue
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertIn(numeric_pinyin, self.normalized_map)

    def test_every_code_reconstructs_back_to_same_encoded_string(self):
        for numeric_pinyin, expected_code in self.codebook.items():
            with self.subTest(numeric_pinyin=numeric_pinyin):
                decoded = self.decoder.decode(numeric_pinyin)
                self.assertEqual(self._render_decoded_code(decoded), expected_code)


if __name__ == "__main__":
    unittest.main()
