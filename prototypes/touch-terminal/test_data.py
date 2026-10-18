"""Generated concept keyboard contracts and source drift guards."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from physical_layout import ROOT, SOURCE, ENGLISH_SOURCE, OUTPUT, build, parse_physical_kle


class GeneratedPhysicalDataTests(unittest.TestCase):
    def test_generated_matches_current_sources(self):
        expected = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
        self.assertEqual(expected, OUTPUT.read_text(encoding="utf-8"))

    def test_projection_is_case_sensitive_and_all_75_are_enabled(self):
        layout = build()
        ids = {identifier: key for key in layout["keys"] for identifier in key["yinyuanIds"]}
        self.assertEqual("I", ids["M01"]["action"]["ascii"])
        self.assertEqual("i", ids["M03"]["action"]["ascii"])
        self.assertEqual("'", ids["N12"]["action"]["ascii"])
        self.assertEqual("`", ids["N26"]["action"]["ascii"])
        for identifier,char in (("M25","B"),("M26","M"),("M27","P")):
            self.assertEqual(char,ids[identifier]["action"]["ascii"])
            self.assertEqual([],ids[identifier]["disabledYinyuanIds"])
        alphabet = {key[action]["ascii"] for key in layout["keys"]
                    for action, identifiers in (("action", "baseYinyuanIds"), ("shiftAction", "shiftYinyuanIds"))
                    if key.get(identifiers)}
        self.assertEqual(75, len(alphabet))
        self.assertTrue(set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") <= alphabet)
        self.assertFalse(set("1234567890") & alphabet)

    def test_input_adaptation_preserves_all_frozen_kle_geometry_and_legends(self):
        frozen = parse_physical_kle(json.loads(SOURCE.read_text(encoding="utf-8-sig")))
        layout = build()
        self.assertEqual(frozen["bounds"], layout["bounds"])
        self.assertEqual(len(frozen["keys"]), len(layout["keys"]))
        for original, generated in zip(frozen["keys"], layout["keys"]):
            self.assertEqual(original, {field: generated[field] for field in original})

    def test_changed_ascii_annotation_fails_instead_of_becoming_a_second_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("internal_data/manual_key_layout.json", str(SOURCE.relative_to(ROOT)), str(ENGLISH_SOURCE.relative_to(ROOT)),
                             "docs/project/connected_speech/erhua_sound_key_projection.json"):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            source = root / SOURCE.relative_to(ROOT)
            raw = json.loads(source.read_text(encoding="utf-8"))
            for row in raw:
                if isinstance(row, list):
                    for index, value in enumerate(row):
                        if isinstance(value, str) and "M01" in value:
                            row[index] = value.replace("\nI", "\nZ")
            source.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "annotation disagrees"):
                build(root)

if __name__ == "__main__":
    unittest.main()
