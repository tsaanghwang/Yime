"""Physical board import contracts, independent from historical 60-button demo."""
import json
import unittest

from physical_layout import SOURCE, build, key_action, parse_physical_kle, plain


class PhysicalLayoutTests(unittest.TestCase):
    def test_supplied_board_geometry_and_inventory(self):
        layout = parse_physical_kle(json.loads(SOURCE.read_text(encoding="utf-8-sig")))
        self.assertEqual(129, len(layout["keys"]))
        self.assertEqual({"width": 25.75, "height": 7.25}, layout["bounds"])
        ids = [item for key in layout["keys"] for item in key["yinyuanIds"]]
        self.assertEqual(60, len(ids))
        self.assertEqual(60, len(set(ids)))
        shared = [k["yinyuanIds"] for k in layout["keys"] if len(k["yinyuanIds"]) > 1]
        self.assertCountEqual(shared, [["M29", "M26"], ["M28", "M25"], ["M30", "M27"]])

    def test_kle_row_offsets_persist(self):
        keys = parse_physical_kle([["a"], [{"y": .25}, "b"], ["c"]])["keys"]
        self.assertEqual([0, 1.25, 2.25], [k["y"] for k in keys])

    def test_alignment_7_and_5(self):
        keys = parse_physical_kle([[{"a": 7, "w": 2}, "Tab", {"a": 5}, "N\nN\n\n\n\n\nM29|M26"]])["keys"]
        self.assertEqual("Tab", keys[0]["labels"][4])
        self.assertEqual("M29|M26", keys[1]["labels"][4])
        self.assertEqual("N", keys[1]["labels"][1])
        self.assertEqual("N", keys[1]["labels"][7])
        self.assertEqual(1, keys[1]["width"])

    def test_empty_metadata(self):
        self.assertEqual(1, len(parse_physical_kle([{}, ["x"]])["keys"]))

    def test_rejects_overlap_rotation_and_invisible_labels(self):
        for source in ([["a", {"x": -.5}, "b"]], [[{"r": 10}, "a"]], [[{"a": 7}, "a\nb"]]):
            with self.assertRaises(ValueError):
                parse_physical_kle(source)

    def test_html_legend_is_annotation_not_code(self):
        self.assertEqual("ĉ", plain("c&#770;"))
        self.assertEqual("o\u0305", plain("<span class='cd'>o&#773;</span>"))

    def test_only_explicit_shift_label_is_candidate_action(self):
        candidate = dict(id="test", yinyuanIds=[], labels=["!", "1", "⇧1"])
        self.assertEqual({"type": "select", "ordinal": 1}, key_action(candidate, {}, set()))
        candidate["labels"] = ["1", "End"]
        self.assertEqual({"type": "input", "ascii": "1"}, key_action(candidate, {}, set()))

    def test_concept_candidate_labels_are_plain_ordinals_without_changing_actions(self):
        layout = build()
        candidates = [key for key in layout["keys"] if key["action"]["type"] == "select"]
        self.assertEqual(list(range(1, 10)), [key["action"]["ordinal"] for key in candidates])
        for key in candidates:
            ordinal = str(key["action"]["ordinal"])
            self.assertEqual([ordinal], [label for label in key["displayLabels"] if label])
            self.assertEqual(ordinal, key["displayLabels"][4])
            self.assertIn("⇧" + ordinal, key["labels"])
        for key in layout["keys"]:
            if key["action"]["type"] != "select":
                self.assertNotIn("displayLabels", key)

    def test_noncoding_caps_use_base_legend_and_space_confirms(self):
        keys = parse_physical_kle([["~\n`", ")\n0", "7\nHome", {"a": 7}, "Enter", ""]])["keys"]
        self.assertEqual([{"type": "input", "ascii": "`"}, {"type": "input", "ascii": "0"},
                          {"type": "input", "ascii": "7"}, {"type": "confirm", "key": "Enter"},
                          {"type": "confirm", "key": "Space"}],
                         [key_action(key, {}, set()) for key in keys])

    def test_disabled_shared_owner_is_not_a_second_input(self):
        key = dict(id="test", yinyuanIds=["M28", "M25"], labels=["[", "M28|M25"])
        self.assertEqual({"type": "input", "ascii": "["},
                         key_action(key, {"M28": "[", "M25": "["}, {"M25"}))
        with self.assertRaises(ValueError):
            key_action(key, {"M28": "]", "M25": "]"}, {"M25"})


if __name__ == "__main__":
    unittest.main()
