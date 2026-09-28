"""Contracts for the supported Keyboard Layout Editor import subset."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from kle_layout import load_kle, parse_kle

IDS = [*(f"N{i:02d}" for i in range(1, 28)), *(f"M{i:02d}" for i in range(1, 34))]
HERE = Path(__file__).resolve().parent


class KLELayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.path = HERE / "design" / "touch-terminal-60.kle.json"
        self.source = json.loads(self.path.read_text(encoding="utf-8"))

    def test_checked_in_template_has_exact_identity_and_geometry(self) -> None:
        parsed, digest = load_kle(self.path, IDS)
        self.assertEqual([key["id"] for key in parsed["keys"]], IDS)
        self.assertEqual(parsed["bounds"], {"width": 10.0, "height": 6.0})
        self.assertEqual(len(digest), 64)
        self.assertEqual(parsed["keys"][0]["color"], "#e4eee7")
        self.assertEqual(parsed["keys"][27]["color"], "#f4e4cf")

    def test_offsets_and_rectangular_sizes_are_preserved(self) -> None:
        source = copy.deepcopy(self.source)
        source[1].insert(1, {"x": 0.5, "w": 1.5, "h": 0.8})
        parsed = parse_kle(source, IDS)
        first = parsed["keys"][0]
        self.assertEqual((first["x"], first["y"], first["width"], first["height"]), (0.5, 0.0, 1.5, 0.8))
        self.assertEqual(parsed["keys"][1]["x"], 2.0)

    def test_rejects_missing_duplicate_unknown_overlap_and_rotation(self) -> None:
        cases = {}
        missing = copy.deepcopy(self.source)
        missing[-1].pop()
        cases["missing"] = missing
        duplicate = copy.deepcopy(self.source)
        duplicate[-1][-1] = "N01"
        cases["duplicate"] = duplicate
        unknown = copy.deepcopy(self.source)
        unknown[-1][-1] = "M34"
        cases["unknown"] = unknown
        overlap = copy.deepcopy(self.source)
        overlap[1].insert(2, {"x": -0.5})
        cases["overlap"] = overlap
        rotated = copy.deepcopy(self.source)
        rotated[1].insert(1, {"r": 10})
        cases["rotated"] = rotated
        for name, source in cases.items():
            with self.subTest(name=name), self.assertRaises(ValueError):
                parse_kle(source, IDS)

    def test_download_must_be_strict_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "raw-data.txt"
            for name, source in {
                "relaxed-members": '[{name:"relaxed raw data"},["N01"]]',
                "nan": '[{"ignored":NaN},["N01"]]',
                "positive-infinity": '[{"ignored":Infinity},["N01"]]',
                "negative-infinity": '[{"ignored":-Infinity},["N01"]]',
            }.items():
                with self.subTest(name=name):
                    path.write_text(source, encoding="utf-8")
                    with self.assertRaisesRegex(ValueError, "strict JSON"):
                        load_kle(path, IDS)


if __name__ == "__main__":
    unittest.main()
