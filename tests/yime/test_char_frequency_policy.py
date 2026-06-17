import sqlite3
import tempfile
import unittest
from pathlib import Path

from yime.utils.char_frequency_policy import (
    BCC_SOURCE,
    SYNTHETIC_NONE_SOURCE,
    build_hanzi_frequency_table,
    import_hanzi_frequency_rows,
    resolve_char_frequency,
    synthetic_frequency_from_unihan_columns,
)


class TestCharFrequencyPolicy(unittest.TestCase):
    def test_bcc_frequency_overrides_unihan_columns(self) -> None:
        resolved = resolve_char_frequency(
            bcc_frequency=12345,
            unihan_columns={"kTGHZ2013": "zhong1"},
        )
        self.assertEqual(resolved.frequency, 12345)
        self.assertEqual(resolved.source, BCC_SOURCE)

    def test_synthetic_uses_max_unihan_tier(self) -> None:
        resolved = resolve_char_frequency(
            bcc_frequency=None,
            unihan_columns={
                "kMandarin": "zhong1",
                "kXHC1983": "zhong1",
            },
        )
        self.assertEqual(resolved.frequency, 3)
        self.assertEqual(resolved.source, "synthetic/kXHC1983")

    def test_tghz2013_synthetic_is_five(self) -> None:
        resolved = synthetic_frequency_from_unihan_columns({"kTGHZ2013": "zhong1"})
        self.assertEqual(resolved.frequency, 5)
        self.assertEqual(resolved.source, "synthetic/kTGHZ2013")

    def test_hanyu_pinlu_synthetic_is_flat_four(self) -> None:
        resolved = synthetic_frequency_from_unihan_columns(
            {"kHanyuPinlu": "zhong1(100) ma3(20)"}
        )
        self.assertEqual(resolved.frequency, 4)
        self.assertEqual(resolved.source, "synthetic/kHanyuPinlu")

    def test_no_unihan_columns_is_zero(self) -> None:
        resolved = resolve_char_frequency(bcc_frequency=None, unihan_columns={})
        self.assertEqual(resolved.frequency, 0)
        self.assertEqual(resolved.source, SYNTHETIC_NONE_SOURCE)

    def test_phrase_lexicon_default_is_one_without_bcc(self) -> None:
        from yime.utils.char_frequency_policy import (
            PHRASE_LEXICON_DEFAULT_FREQUENCY,
            resolve_phrase_frequency,
        )

        self.assertEqual(resolve_phrase_frequency(None), PHRASE_LEXICON_DEFAULT_FREQUENCY)
        self.assertEqual(resolve_phrase_frequency(120), 120)

    def test_import_hanzi_frequency_rows_writes_effective_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            freq_path = temp_path / "merged_char_freq.txt"
            freq_path.write_text("char,freq\n的,100\n", encoding="utf-8")
            db_path = temp_path / "unihan.db"

            conn = sqlite3.connect(db_path)
            try:
                conn.executescript(
                    """
                    CREATE TABLE hanzi (
                        codepoint TEXT PRIMARY KEY,
                        hanzi TEXT NOT NULL
                    );
                    CREATE TABLE unihan_readings_clean (
                        codepoint TEXT PRIMARY KEY,
                        kTGHZ2013 TEXT,
                        kHanyuPinlu TEXT,
                        kXHC1983 TEXT,
                        kHanyuPinyin TEXT,
                        kMandarin TEXT
                    );
                    INSERT INTO hanzi (codepoint, hanzi) VALUES
                        ('U+7684', '的'),
                        ('U+4E00', '一'),
                        ('U+671F', '期');
                    INSERT INTO unihan_readings_clean (
                        codepoint, kTGHZ2013, kHanyuPinlu, kXHC1983, kHanyuPinyin, kMandarin
                    ) VALUES
                        ('U+7684', 'de5', NULL, NULL, NULL, 'de5'),
                        ('U+4E00', NULL, NULL, NULL, NULL, 'yi1'),
                        ('U+671F', 'qi1', NULL, NULL, NULL, 'qi1');
                    """
                )
                conn.commit()
                cur = conn.cursor()
                build_hanzi_frequency_table(cur)
                conn.commit()
                bcc_applied, synthetic_applied, _skipped = import_hanzi_frequency_rows(
                    cur,
                    freq_path=freq_path,
                    unihan_db_path=db_path,
                )
                conn.commit()
                rows = {
                    row[0]: (row[1], row[2])
                    for row in cur.execute(
                        """
                        SELECT h.hanzi, hf.frequency, hf.frequency_source
                        FROM hanzi h
                        JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
                        ORDER BY h.hanzi
                        """
                    )
                }
            finally:
                conn.close()

            self.assertEqual(bcc_applied, 1)
            self.assertEqual(synthetic_applied, 2)
            self.assertEqual(rows["的"], (100, BCC_SOURCE))
            self.assertEqual(rows["期"], (5, "synthetic/kTGHZ2013"))
            self.assertEqual(rows["一"], (1, "synthetic/kMandarin"))


if __name__ == "__main__":
    unittest.main()
