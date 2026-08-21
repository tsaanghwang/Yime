import sqlite3
import tempfile
import unittest
from pathlib import Path

from syllable.codec.yinjie import Yinjie
from yime.utils.yinjie_slot_decomposition import (
    build_decomposition_row,
    ensure_yinjie_slot_decomposition_schema,
    sync_yinjie_slot_decomposition,
)


class TestYinjieSlotDecomposition(unittest.TestCase):
    def test_build_decomposition_row_matches_yinjie(self):
        row = build_decomposition_row("ma1", "ABCD", "test")
        self.assertEqual(row.pinyin_tone, "ma1")
        self.assertEqual(row.yime_code, "ABCD")
        yinjie = Yinjie.from_code("ABCD")
        self.assertEqual(row.slot_shouyin, yinjie.initial)
        self.assertEqual(row.slot_ganyin, yinjie.ganyin_code)
        self.assertEqual(row.slot_huyin, yinjie.ascender)
        self.assertEqual(row.slot_zhuyin, yinjie.peak)
        self.assertEqual(row.slot_moyin, yinjie.descender)
        self.assertEqual(row.slot_yunyin, yinjie.get_yunyin_code())
        self.assertEqual(row.slot_jianyin, yinjie.get_jianyin_code())

    def test_build_decomposition_row_rejects_non_four_code(self):
        with self.assertRaises(ValueError):
            build_decomposition_row("ma1", "ABC", "test")

    def test_sync_from_pinyin_yime_code(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "test.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.execute(
                    """
                    CREATE TABLE pinyin_yime_code (
                        pinyin_tone TEXT PRIMARY KEY,
                        yime_code TEXT NOT NULL,
                        code_source TEXT NOT NULL,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    )
                    """
                )
                conn.execute(
                    """
                    INSERT INTO pinyin_yime_code (pinyin_tone, yime_code, code_source)
                    VALUES ('ma1', 'ABCD', 'yinjie_code'), ('ni3', 'EFGH', 'yinjie_code')
                    """
                )
                count = sync_yinjie_slot_decomposition(conn)
                self.assertEqual(count, 2)
                ensure_yinjie_slot_decomposition_schema(conn)
                rows = conn.execute(
                    """
                    SELECT pinyin_tone, yime_code, slot_shouyin, slot_ganyin, slot_jianyin
                    FROM yinjie_slot_decomposition
                    ORDER BY pinyin_tone
                    """
                ).fetchall()
                self.assertEqual(
                    rows,
                    [
                        ("ma1", "ABCD", "A", "BCD", "BC"),
                        ("ni3", "EFGH", "E", "FGH", "FG"),
                    ],
                )
            finally:
                conn.close()


if __name__ == "__main__":
    unittest.main()
