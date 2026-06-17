import sqlite3
import tempfile
import unittest
from pathlib import Path

from yime.utils.blcu_word_frequency_import import (
    apply_frequency_updates,
    load_char_frequency_map,
    load_phrase_frequency_map,
    migrate_phrase_frequency_column_to_integer,
    phrase_frequency_column_type,
    purge_obsolete_frequency_metadata,
)


class TestBlcuWordFrequencyImport(unittest.TestCase):
    def test_load_phrase_frequency_map_keeps_longest_multi_char_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "merged_word_freq.txt"
            path.write_text(
                "word,freq\n"
                "中国,100\n"
                "发展,200\n"
                "的,999\n",
                encoding="utf-8",
            )
            by_phrase, parsed_rows = load_phrase_frequency_map(path)

        self.assertEqual(parsed_rows, 2)
        self.assertEqual(by_phrase, {"中国": 100, "发展": 200})

    def test_load_char_frequency_map_reads_single_char_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "single_char_freq.txt"
            path.write_text(
                "char,freq\n"
                "的,5230487\n"
                "中国,100\n",
                encoding="utf-8",
            )
            by_char, parsed_rows = load_char_frequency_map(path)

        self.assertEqual(parsed_rows, 1)
        self.assertEqual(by_char, {"的": 5230487})

    def test_apply_frequency_updates_dry_run_only_counts_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "pinyin_hanzi.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.executescript(
                    """
                    CREATE TABLE phrase_inventory (
                        id INTEGER PRIMARY KEY,
                        phrase TEXT NOT NULL,
                        phrase_frequency INTEGER,
                        phrase_length INTEGER NOT NULL
                    );
                    CREATE TABLE char_inventory (
                        id INTEGER PRIMARY KEY,
                        hanzi TEXT NOT NULL,
                        char_frequency_abs INTEGER,
                        char_frequency_rel REAL,
                        frequency_source TEXT
                    );
                    CREATE TABLE char_pinyin_map (
                        char_id INTEGER,
                        numeric_pinyin_id INTEGER,
                        reading_weight REAL
                    );
                    CREATE TABLE prototype_metadata (
                        key TEXT PRIMARY KEY,
                        value TEXT,
                        note TEXT,
                        updated_at TEXT
                    );
                    INSERT INTO phrase_inventory (id, phrase, phrase_frequency, phrase_length) VALUES
                        (1, '期中', 1, 2),
                        (2, '期终', 1, 2),
                        (3, '独有词', 1, 3);
                    INSERT INTO char_inventory (id, hanzi) VALUES
                        (1, '的'),
                        (2, '期');
                    """
                )
                conn.commit()
            finally:
                conn.close()

            stats = apply_frequency_updates(
                db_path,
                phrase_frequency_by_text={"期中": 120, "期终": 80},
                char_frequency_by_char={"的": 5000},
                source_tag="test/BCC",
                phrase_source="phrase.csv",
                char_source="char.csv",
                unihan_db_path=Path(temp_dir) / "missing-unihan.db",
                dry_run=True,
            )

            self.assertEqual(stats.matched_phrase_rows, 2)
            self.assertEqual(stats.matched_char_rows, 1)
            self.assertEqual(stats.synthetic_char_rows, 0)
            self.assertEqual(stats.unmatched_phrase_rows, 1)
            self.assertEqual(stats.unmatched_char_rows, 1)

            conn = sqlite3.connect(db_path)
            try:
                self.assertEqual(
                    conn.execute(
                        "SELECT phrase_frequency FROM phrase_inventory WHERE phrase = '期中'"
                    ).fetchone()[0],
                    1,
                )
            finally:
                conn.close()

    def test_apply_frequency_updates_writes_lexicon_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "pinyin_hanzi.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.executescript(
                    """
                    CREATE TABLE phrase_inventory (
                        id INTEGER PRIMARY KEY,
                        phrase TEXT NOT NULL,
                        phrase_frequency REAL,
                        phrase_length INTEGER NOT NULL,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    CREATE TABLE char_inventory (
                        id INTEGER PRIMARY KEY,
                        hanzi TEXT NOT NULL,
                        char_frequency_abs INTEGER,
                        char_frequency_rel REAL,
                        frequency_source TEXT,
                        updated_at TEXT
                    );
                    CREATE TABLE char_pinyin_map (
                        char_id INTEGER,
                        numeric_pinyin_id INTEGER,
                        reading_weight REAL,
                        updated_at TEXT
                    );
                    CREATE TABLE prototype_metadata (
                        key TEXT PRIMARY KEY,
                        value TEXT,
                        note TEXT,
                        updated_at TEXT
                    );
                    INSERT INTO phrase_inventory (id, phrase, phrase_frequency, phrase_length) VALUES
                        (1, '期中', 1, 2),
                        (2, '独有词', 1, 3);
                    INSERT INTO char_inventory (id, hanzi) VALUES
                        (1, '的'),
                        (2, '期');
                    INSERT INTO char_pinyin_map (char_id, numeric_pinyin_id, reading_weight)
                    VALUES (1, 1, 9.0);
                    """
                )
                conn.commit()
            finally:
                conn.close()

            stats = apply_frequency_updates(
                db_path,
                phrase_frequency_by_text={"期中": 120},
                char_frequency_by_char={"的": 5000},
                source_tag="test/BCC",
                phrase_source="phrase.csv",
                char_source="char.csv",
                unihan_db_path=Path(temp_dir) / "missing-unihan.db",
                dry_run=False,
            )

            self.assertEqual(stats.matched_phrase_rows, 1)
            self.assertEqual(stats.matched_char_rows, 1)
            self.assertEqual(stats.synthetic_char_rows, 0)

            conn = sqlite3.connect(db_path)
            try:
                self.assertEqual(
                    conn.execute(
                        "SELECT phrase_frequency FROM phrase_inventory WHERE phrase = '期中'"
                    ).fetchone()[0],
                    120,
                )
                self.assertEqual(
                    conn.execute(
                        "SELECT phrase_frequency FROM phrase_inventory WHERE phrase = '独有词'"
                    ).fetchone()[0],
                    1,
                )
                row = conn.execute(
                    "SELECT char_frequency_abs, char_frequency_rel, frequency_source "
                    "FROM char_inventory WHERE hanzi = '的'"
                ).fetchone()
                self.assertEqual(row, (5000, None, "test/BCC"))
                period_row = conn.execute(
                    "SELECT char_frequency_abs, frequency_source "
                    "FROM char_inventory WHERE hanzi = '期'"
                ).fetchone()
                self.assertEqual(period_row, (0, "synthetic/none"))
                self.assertIsNone(
                    conn.execute(
                        "SELECT reading_weight FROM char_pinyin_map"
                    ).fetchone()[0]
                )
            finally:
                conn.close()

    def test_purge_obsolete_frequency_metadata_removes_legacy_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "pinyin_hanzi.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.execute(
                    """
                    CREATE TABLE prototype_metadata (
                        key TEXT PRIMARY KEY,
                        value TEXT,
                        note TEXT,
                        updated_at TEXT
                    )
                    """
                )
                conn.executemany(
                    """
                    INSERT INTO prototype_metadata (key, value, note, updated_at)
                    VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                    """,
                    [
                        (
                            "prototype_xiandaihaiyu_phrase_freq_updated",
                            "3965",
                            "legacy",
                        ),
                        (
                            "prototype_8105_frequency_source",
                            "legacy.yaml",
                            "legacy",
                        ),
                        (
                            "prototype_char_frequency_bridge_total_chars",
                            "44360",
                            "legacy bridge snapshot",
                        ),
                        (
                            "prototype_blcu_word_freq_phrase_matched",
                            "1",
                            "current",
                        ),
                    ],
                )
                conn.commit()
                removed = purge_obsolete_frequency_metadata(conn)
                conn.commit()
                remaining = {
                    row[0]
                    for row in conn.execute("SELECT key FROM prototype_metadata")
                }
            finally:
                conn.close()

            self.assertEqual(
                set(removed),
                {
                    "prototype_xiandaihaiyu_phrase_freq_updated",
                    "prototype_8105_frequency_source",
                    "prototype_char_frequency_bridge_total_chars",
                },
            )
            self.assertEqual(remaining, {"prototype_blcu_word_freq_phrase_matched"})


    def test_migrate_phrase_frequency_column_to_integer(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "pinyin_hanzi.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.executescript(
                    """
                    CREATE TABLE phrase_inventory (
                        id INTEGER PRIMARY KEY,
                        phrase TEXT NOT NULL UNIQUE,
                        yime_code TEXT,
                        phrase_frequency REAL,
                        phrase_length INTEGER NOT NULL,
                        is_common_phrase INTEGER NOT NULL DEFAULT 1,
                        legacy_phrase_id INTEGER,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    INSERT INTO phrase_inventory (id, phrase, phrase_frequency, phrase_length)
                    VALUES (1, '中国', 3258176.0, 2);
                    """
                )
                conn.commit()
                self.assertEqual(phrase_frequency_column_type(conn), "REAL")
                migrated = migrate_phrase_frequency_column_to_integer(conn)
                conn.commit()
                self.assertTrue(migrated)
                self.assertEqual(phrase_frequency_column_type(conn), "INTEGER")
                row = conn.execute(
                    "SELECT phrase_frequency, typeof(phrase_frequency) "
                    "FROM phrase_inventory WHERE phrase = '中国'"
                ).fetchone()
                self.assertEqual(row, (3258176, "integer"))
            finally:
                conn.close()


@unittest.skipUnless(
    Path("external_data/word_freq/merged_word_freq.txt").exists(),
    "requires BCC merged word frequency file",
)
class TestBlcuWordFrequencyImportAgainstRuntime(unittest.TestCase):
    def test_runtime_lexicon_has_substantial_bcc_overlap(self) -> None:
        phrase_freq, _ = load_phrase_frequency_map(
            Path("external_data/word_freq/merged_word_freq.txt")
        )
        conn = sqlite3.connect("yime/pinyin_hanzi.db")
        try:
            phrases = {
                str(row[0])
                for row in conn.execute(
                    "SELECT DISTINCT phrase FROM phrase_inventory WHERE LENGTH(phrase) > 1"
                )
            }
        finally:
            conn.close()

        overlap = phrases & set(phrase_freq)
        self.assertGreater(len(overlap), 100_000)
        self.assertGreater(len(overlap) / len(phrases), 0.45)


if __name__ == "__main__":
    unittest.main()
