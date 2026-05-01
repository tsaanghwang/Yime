import json
import unittest
from pathlib import Path

from internal_data.pinyin_source_db.build_source_pinyin_db import marked_syllable_to_numeric
from syllable.analysis.slice.yinjie_encoder import YinjieEncoder
from yinjie_decoder import YinjieDecoder


class TestPinyinBidirectionalValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.normalized_path = Path("pinyin/hanzi_pinyin/pinyin_normalized.json")
        cls.codebook_path = Path("yinjie_code.json")

        with cls.normalized_path.open("r", encoding="utf-8") as file:
            cls.normalized_map = json.load(file)

        with cls.codebook_path.open("r", encoding="utf-8") as file:
            cls.codebook = json.load(file)

        cls.encoder = YinjieEncoder()
        cls.decoder = YinjieDecoder(code_file=cls.codebook_path)

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

    def test_normalized_and_codebook_keys_match_exactly(self):
        self.assertEqual(set(self.normalized_map), set(self.codebook))

    def test_every_normalized_key_encodes_to_checked_in_code(self):
        for numeric_pinyin, expected_code in self.codebook.items():
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertEqual(self.encoder.encode_single_yinjie(numeric_pinyin), expected_code)

    def test_every_marked_value_round_trips_back_to_original_numeric_key(self):
        for numeric_pinyin, marked_pinyin in self.normalized_map.items():
            with self.subTest(numeric_pinyin=numeric_pinyin, marked_pinyin=marked_pinyin):
                self.assertEqual(marked_syllable_to_numeric(marked_pinyin), numeric_pinyin)

    def test_every_codebook_key_is_present_in_normalized_mapping(self):
        for numeric_pinyin in self.codebook:
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertIn(numeric_pinyin, self.normalized_map)

    def test_every_code_reconstructs_back_to_same_encoded_string(self):
        for numeric_pinyin, expected_code in self.codebook.items():
            with self.subTest(numeric_pinyin=numeric_pinyin):
                decoded = self.decoder.decode(numeric_pinyin)
                self.assertEqual(self._render_decoded_code(decoded), expected_code)


if __name__ == "__main__":
    unittest.main()
