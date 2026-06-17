import json
import sqlite3
import unittest
from collections import defaultdict
from pathlib import Path

from syllable.codec.paths import YINJIE_CODE_PATH
from syllable.codec.yinjie_decoder import YinjieDecoder
from syllable.codec.yinjie_encoder import YinjieEncoder


class TestYinjieRoundTrip(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.normalized_path = Path("internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json")
        cls.codebook_path = YINJIE_CODE_PATH

        with cls.normalized_path.open("r", encoding="utf-8") as file:
            cls.normalized_pinyin = list(json.load(file).keys())

        with cls.codebook_path.open("r", encoding="utf-8") as file:
            cls.checked_in_codebook = json.load(file)

        cls.encoder = YinjieEncoder()
        cls.decoder = YinjieDecoder(code_file=cls.codebook_path)
        cls.code_to_pinyin = defaultdict(list)
        for pinyin, code in cls.checked_in_codebook.items():
            cls.code_to_pinyin[code].append(pinyin)

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

    def test_codebook_keys_with_lexicon_attestation_are_in_normalized(self):
        db_path = Path(".generated/source_pinyin.db")
        if not db_path.exists():
            self.skipTest("inventory table not available")
        conn = sqlite3.connect(db_path)
        try:
            inventory_keys = {
                row[0]
                for row in conn.execute(
                    "SELECT DISTINCT numeric_syllable "
                    "FROM m_distinct_syllable_inventory"
                )
            }
        finally:
            conn.close()

        for pinyin in self.checked_in_codebook:
            if pinyin not in inventory_keys:
                continue
            with self.subTest(pinyin=pinyin):
                self.assertIn(pinyin, self.normalized_pinyin)

    def test_codebook_covered_entries_round_trip_to_same_code_and_alias_group(self):
        for pinyin in self.normalized_pinyin:
            if pinyin not in self.checked_in_codebook:
                continue
            with self.subTest(pinyin=pinyin):
                encoded = self.encoder.encode_single_yinjie(pinyin)
                decoded = self.decoder.decode(pinyin)
                reconstructed = self._render_decoded_code(decoded)

                self.assertEqual(self.checked_in_codebook[pinyin], encoded)
                self.assertEqual(encoded, reconstructed)
                self.assertIn(pinyin, self.code_to_pinyin[reconstructed])

    def test_all_normalized_pinyin_round_trip_when_codebook_is_current(self):
        if set(self.normalized_pinyin) != set(self.checked_in_codebook):
            self.skipTest("codebook not yet expanded to inventory export domain")
        for pinyin in self.normalized_pinyin:
            with self.subTest(pinyin=pinyin):
                encoded = self.encoder.encode_single_yinjie(pinyin)
                decoded = self.decoder.decode(pinyin)
                reconstructed = self._render_decoded_code(decoded)

                self.assertEqual(self.checked_in_codebook[pinyin], encoded)
                self.assertEqual(encoded, reconstructed)
                self.assertIn(pinyin, self.code_to_pinyin[reconstructed])

    def test_code_collisions_still_decode_to_a_single_stable_structure(self):
        for code, alias_group in self.code_to_pinyin.items():
            if len(alias_group) < 2:
                continue

            with self.subTest(code=code, alias_group=alias_group):
                reconstructed_codes = {
                    self._render_decoded_code(self.decoder.decode(pinyin))
                    for pinyin in alias_group
                }
                encoded_codes = {
                    self.encoder.encode_single_yinjie(pinyin)
                    for pinyin in alias_group
                }

                self.assertEqual(reconstructed_codes, {code})
                self.assertEqual(encoded_codes, {code})


if __name__ == "__main__":
    unittest.main()
