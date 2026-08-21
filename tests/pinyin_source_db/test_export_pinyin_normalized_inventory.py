import json
import importlib.util
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Callable, Iterable, Protocol, cast


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
PINYIN_SOURCE_DB_DIR = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db"
if str(PINYIN_SOURCE_DB_DIR) not in sys.path:
    sys.path.insert(0, str(PINYIN_SOURCE_DB_DIR))

from syllable.codec.paths import YINJIE_CODE_PATH
from yime.utils.marked_pinyin import marked_syllable_to_numeric


_export_spec = importlib.util.spec_from_file_location(
    "export_pinyin_normalized",
    PINYIN_SOURCE_DB_DIR / "export_pinyin_normalized.py",
)
if _export_spec is None or _export_spec.loader is None:
    raise ImportError("Could not load export_pinyin_normalized module")
_export_pinyin_normalized = importlib.util.module_from_spec(_export_spec)
_export_spec.loader.exec_module(_export_pinyin_normalized)


class _ExportPinyinNormalizedModule(Protocol):
    collect_numeric_to_marked_pairs: Callable[[sqlite3.Connection, str], dict[str, set[str]]]
    load_inventory_numeric_syllables: Callable[[sqlite3.Connection, str], Iterable[str]]


_typed_export_pinyin_normalized = cast(_ExportPinyinNormalizedModule, _export_pinyin_normalized)


collect_numeric_to_marked_pairs = _typed_export_pinyin_normalized.collect_numeric_to_marked_pairs
load_inventory_numeric_syllables = _typed_export_pinyin_normalized.load_inventory_numeric_syllables


EXPORT_SCRIPT = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "export_pinyin_normalized.py"
DEFAULT_DB = (
    WORKSPACE_ROOT / ".generated" / "lexicon_source_bundle" / "source_lexicon.sqlite3"
)
INVENTORY_TABLE = "m_distinct_syllable_inventory"
NORMALIZED_PATH = (
    WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "lexicon_exports" / "pinyin_normalized.json"
)
PATCH_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "pinyin_normalized_patch.json"


def refresh_inventory(db_path: Path) -> None:
    command = [
        sys.executable,
        str(WORKSPACE_ROOT / "tools" / "refresh_materialized_syllable_inventory.py"),
        "--db-path",
        str(db_path),
    ]
    subprocess.run(command, check=True, cwd=WORKSPACE_ROOT)


@unittest.skipUnless(DEFAULT_DB.exists(), "requires unified source_lexicon.sqlite3")
class TestExportPinyinNormalizedInventoryDomain(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db_path = DEFAULT_DB
        conn = sqlite3.connect(cls.db_path)
        try:
            cls.inventory_keys = set(load_inventory_numeric_syllables(conn, INVENTORY_TABLE))
        finally:
            conn.close()

        with NORMALIZED_PATH.open("r", encoding="utf-8") as handle:
            cls.exported = json.load(handle)

        with YINJIE_CODE_PATH.open("r", encoding="utf-8") as handle:
            cls.codebook = json.load(handle)

        cls.patch_keys: set[str] = (
            set(cast(dict[str, object], json.loads(PATCH_PATH.read_text(encoding="utf-8"))).keys())
            if PATCH_PATH.exists()
            else set[str]()
        )

    def test_export_covers_lexicon_inventory_and_patch(self):
        self.assertTrue(self.inventory_keys)
        expected = self.inventory_keys | self.patch_keys
        self.assertEqual(expected, set(self.exported))

    def test_codebook_keys_with_lexicon_attestation_remain_in_export(self):
        attested = set(self.codebook) & self.inventory_keys
        self.assertTrue(attested)
        self.assertLessEqual(attested, set(self.exported))

    def test_export_beyond_codebook_are_lexicon_attested_or_patch(self):
        extra = set(self.exported) - set(self.codebook)
        if not extra:
            self.skipTest("codebook already covers export domain")
        self.assertEqual(extra, (extra & self.inventory_keys) | (extra & self.patch_keys))

    def test_every_exported_key_round_trips_marked_to_numeric(self):
        for numeric_pinyin, marked_pinyin in self.exported.items():
            with self.subTest(numeric_pinyin=numeric_pinyin):
                self.assertEqual(marked_syllable_to_numeric(marked_pinyin), numeric_pinyin)

    def test_er5_uses_restored_full_form(self):
        self.assertIn("er5", self.exported)
        self.assertEqual(self.exported["er5"], "er")


class TestExportPinyinNormalizedInventoryCollection(unittest.TestCase):
    def test_phrase_only_syllables_use_inventory_marked_forms(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / "source.db"
            conn = sqlite3.connect(db_path)
            try:
                conn.executescript(
                    """
                    CREATE TABLE char_readings (
                        numeric_pinyin TEXT NOT NULL,
                        marked_pinyin TEXT NOT NULL
                    );
                    CREATE TABLE m_distinct_syllable_inventory (
                        numeric_syllable TEXT NOT NULL,
                        marked_syllable TEXT NOT NULL,
                        source_tables TEXT NOT NULL,
                        has_single_char INTEGER NOT NULL,
                        has_phrase INTEGER NOT NULL,
                        single_char_distinct_count INTEGER NOT NULL,
                        phrase_distinct_count INTEGER NOT NULL,
                        flattened_distinct_count INTEGER NOT NULL,
                        PRIMARY KEY (numeric_syllable, marked_syllable)
                    ) WITHOUT ROWID;
                    INSERT INTO char_readings VALUES ('ma1', 'mā'), ('er5', 'r');
                    INSERT INTO m_distinct_syllable_inventory VALUES
                        ('ma1', 'mā', 'single_char', 1, 0, 1, 0, 1),
                        ('xing5', 'xing', 'phrase', 0, 1, 0, 1, 1),
                        ('er5', 'r', 'single_char', 1, 0, 1, 0, 1),
                        ('er5', 'er', 'phrase', 0, 1, 0, 1, 1);
                    """
                )
                mapping = collect_numeric_to_marked_pairs(conn, INVENTORY_TABLE)
            finally:
                conn.close()

        self.assertEqual(mapping["ma1"], {"mā"})
        self.assertEqual(mapping["xing5"], {"xing"})
        self.assertEqual(mapping["er5"], {"r"})


@unittest.skipUnless(DEFAULT_DB.exists(), "requires unified source_lexicon.sqlite3")
class TestExportPinyinNormalizedInventoryScript(unittest.TestCase):
    def test_inventory_domain_export_writes_full_inventory(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "pinyin_normalized.json"
            command = [
                sys.executable,
                str(EXPORT_SCRIPT),
                "--db",
                str(DEFAULT_DB),
                "--output",
                str(output_path),
                "--export-domain",
                "inventory",
                "--allow-validation-warnings",
            ]
            completed = subprocess.run(
                command,
                check=True,
                cwd=WORKSPACE_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertIn("export_domain: inventory", completed.stdout)

            payload = json.loads(output_path.read_text(encoding="utf-8"))
            conn = sqlite3.connect(DEFAULT_DB)
            try:
                inventory_keys = set(load_inventory_numeric_syllables(conn, INVENTORY_TABLE))
            finally:
                conn.close()
            patch_keys: set[str] = (
                set(cast(dict[str, object], json.loads(PATCH_PATH.read_text(encoding="utf-8"))).keys())
                if PATCH_PATH.exists()
                else set[str]()
            )
            self.assertEqual(set(payload), inventory_keys | patch_keys)


if __name__ == "__main__":
    unittest.main()
