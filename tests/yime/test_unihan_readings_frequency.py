import sqlite3
import unittest
from pathlib import Path

from yime.utils.unihan_readings_frequency import load_tghz2013_char_frequencies

@unittest.skipUnless(
    Path("external_data/unihan_readings/unihan_readings.db").exists(),
    "requires unihan_readings.db",
)
class TestUnihanReadingsFrequency(unittest.TestCase):
    def test_load_tghz2013_char_frequencies_has_8105_entries(self) -> None:
        by_char = load_tghz2013_char_frequencies(
            Path("external_data/unihan_readings/unihan_readings.db")
        )
        self.assertEqual(len(by_char), 8105)
        self.assertGreater(by_char.get("的", 0), 1_000_000)
        self.assertGreater(by_char.get("一", 0), 1_000_000)

    def test_tghz2013_zero_bcc_chars_use_synthetic_five_when_imported(self) -> None:
        conn = sqlite3.connect(
            "external_data/unihan_readings/unihan_readings.db"
        )
        try:
            row = conn.execute(
                """
                SELECT MIN(hf.frequency), MAX(hf.frequency)
                FROM hanzi h
                JOIN unihan_readings_clean u ON h.codepoint = u.codepoint
                JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
                WHERE u.kTGHZ2013 IS NOT NULL AND TRIM(u.kTGHZ2013) <> ''
                  AND hf.frequency_source = 'synthetic/kTGHZ2013'
                """
            ).fetchone()
        finally:
            conn.close()
        if row[0] is None:
            self.skipTest("unihan_readings.db not rebuilt with synthetic frequency policy")
        self.assertEqual(row, (5, 5))


if __name__ == "__main__":
    unittest.main()
