"""Offline fixture contracts. Run: python -m unittest discover -s prototypes/touch-terminal -p test_data.py"""

from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import generate_data as data


class TouchDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.layout = data.build_layout()
        cls.demo = data.build_demo(cls.layout)

    def test_exact_identity_and_case_sensitive_projection(self) -> None:
        keys = {entry["id"]: entry for entry in self.layout["keys"]}
        self.assertEqual(list(keys), data.ID_ORDER)
        self.assertEqual(len(keys), 60)
        self.assertEqual(len({entry["key"] for entry in keys.values()}), 58)
        self.assertEqual((keys["M01"]["key"], keys["M19"]["key"]), ("j", "J"))
        self.assertEqual((keys["M26"]["physicalKey"], keys["M26"]["shift"]), (",", True))
        self.assertEqual(keys["N12"]["sharedWith"], ["N26"])
        self.assertEqual(keys["N26"]["sharedWith"], ["N12"])
        self.assertEqual(keys["N12"]["key"], keys["N26"]["key"])
        self.assertNotEqual(keys["N12"]["symbol"], keys["N26"]["symbol"])
        self.assertEqual(keys["N25"]["sharedWith"], ["N27"])

    def test_demo_ids_are_upstream_and_candidates_are_attested(self) -> None:
        mapping = {entry["id"]: entry["key"] for entry in self.layout["keys"]}
        source_lines = {path: data.text_source(data.ROOT / path).splitlines()
                        for path in data.DEMO_SOURCES}
        self.assertEqual(self.demo["mode"], "demo-fixture-only")
        self.assertEqual(len(self.demo["examples"]), 3)
        self.assertGreater(len(self.demo["examples"][2]["candidates"]), 9)
        for example in self.demo["examples"]:
            self.assertEqual(len(example["ids"]), 4)
            self.assertEqual(example["code"], "".join(mapping[value] for value in example["ids"]))
            self.assertGreaterEqual(len(example["candidates"]), 2)
            source = example["provenance"][0]
            self.assertEqual(source["path"], data.DECOMPOSITION)
            for candidate in example["candidates"]:
                for record in candidate["provenance"]:
                    line = source_lines[record["path"]][record["line"] - 1]
                    self.assertIn(candidate["text"], line.split("\t"))

    def test_checked_in_artifacts_and_drift_detection(self) -> None:
        expected = data.build_artifacts()
        self.assertEqual(data.check_artifacts(data.HERE / "data", expected), [])
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            for name, content in expected.items():
                (target / name).write_text(content, encoding="utf-8")
            corrupted = json.loads(expected["layout.json"])
            corrupted["keys"][0]["key"] = "X"
            (target / "layout.json").write_text(json.dumps(corrupted), encoding="utf-8")
            self.assertEqual(data.check_artifacts(target, expected), ["layout.json"])

    def fixture_root(self, temporary: str) -> Path:
        root = Path(temporary)
        for path in data.LAYOUT_SOURCES:
            destination = root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(data.ROOT / path, destination)
        return root

    def test_reject_missing_duplicate_and_conflicting_canonical_projection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture_root(temporary)
            source = data.read_json(root / data.MANUAL)
            primary = next(item for item in source["layers"] if item["yinyuan_id"] == "M01")
            for kind in ("missing", "duplicate", "unreviewed-share"):
                with self.subTest(kind=kind):
                    broken = copy.deepcopy(source)
                    if kind == "missing":
                        broken["layers"] = [item for item in broken["layers"] if item["yinyuan_id"] != "M01"]
                    elif kind == "duplicate":
                        broken["layers"].append(primary)
                    else:
                        broken["shared_yinyuan_key_groups"][0]["member_yinyuan_ids"] = ["N12", "N01"]
                    (root / data.MANUAL).write_text(json.dumps(broken), encoding="utf-8")
                    with self.assertRaises(ValueError):
                        data.build_layout(root)
            (root / data.MANUAL).write_text(json.dumps(source), encoding="utf-8")
            packaged = data.read_json(root / data.PACKAGED)
            packaged["yinyuan_id_to_key"]["M01"] = "J"
            (root / data.PACKAGED).write_text(json.dumps(packaged), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Packaged layout projection"):
                data.build_layout(root)

    def test_line_endings_do_not_change_text_source_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture_root(temporary)
            expected = data.source_records(root, data.LAYOUT_SOURCES)
            for path in data.LAYOUT_SOURCES:
                content = data.text_source(root / path)
                (root / path).write_bytes(content.replace("\n", "\r\n").encode("utf-8"))
            self.assertEqual(data.source_records(root, data.LAYOUT_SOURCES), expected)
            self.assertEqual(data.build_layout(root), self.layout)


if __name__ == "__main__":
    unittest.main()
