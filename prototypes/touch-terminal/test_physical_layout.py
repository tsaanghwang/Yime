"""Physical geometry and explicit action contracts for the approved concept."""
import json
import unittest

from physical_layout import SOURCE, build, parse_physical_kle, plain, absolute_rectangles, keys_overlap


class PhysicalLayoutTests(unittest.TestCase):
    def test_board_inventory_and_union_geometry(self):
        board = parse_physical_kle(json.loads(SOURCE.read_text(encoding="utf-8-sig")))
        self.assertEqual(138, len(board["keys"]))
        self.assertEqual({"width": 24.75, "height": 7.25}, board["bounds"])
        ids = [identifier for key in board["keys"] for identifier in key["yinyuanIds"]]
        self.assertEqual(75, len(ids))
        self.assertEqual(75, len(set(ids)))
        for index, key in enumerate(board["keys"]):
            self.assertFalse(any(keys_overlap(key, other) for other in board["keys"][index + 1:]))

    def test_iso_union_not_bounding_box_and_cursor_primary_width(self):
        # The lower neighbor occupies the notch, touching but not overlapping.
        board = parse_physical_kle([[{"w": 1, "h": 2, "w2": 2, "h2": 1}, "ISO",
                                     {"x": 1}, "next"], [{"x": 1}, "notch"]])
        self.assertEqual(2, board["keys"][1]["x"])
        self.assertEqual(1, board["keys"][2]["x"])
        self.assertEqual(2, len(board["keys"][0]["rectangles"]))
        with self.assertRaisesRegex(ValueError, "Overlapping"):
            parse_physical_kle([[{"w": 1, "h": 2, "w2": 2, "h2": 1}, "ISO", "collision"]])
        with self.assertRaisesRegex(ValueError, "Overlapping"):
            parse_physical_kle([[{"w": 1, "h": 2, "w2": 2, "h2": 1}, "ISO"],
                                [{"x": .75}, "collision"]])

    def test_secondary_bounds_negative_offsets_and_reset(self):
        board = parse_physical_kle([[{"x": .25, "w": 1, "h": 2, "x2": -.25, "w2": 1.25, "h2": 1},
                                     "ISO", {"x": .25}, "normal"]])
        self.assertEqual(0, min(r["x"] for r in absolute_rectangles(board["keys"][0])))
        self.assertEqual([{"x": 0, "y": 0, "width": 1, "height": 1}], board["keys"][1]["rectangles"])
        with self.assertRaisesRegex(ValueError, "Negative"):
            parse_physical_kle([[{"x2": -.25}, "bad"]])
        self.assertEqual(3, parse_physical_kle([[{"w2": 3}, "wide"]])["bounds"]["width"])

    def test_mirrored_iso_keys(self):
        keys = build()["keys"]
        tab = next(key for key in keys if "Tab" in key["labels"])
        back = next(key for key in keys if key["zone"] == "main" and key["action"]["type"] == "backspace")
        mirror = sorted((24.75 - rect["x"] - rect["width"], rect["y"], rect["width"], rect["height"])
                        for rect in absolute_rectangles(tab))
        actual = sorted((rect["x"], rect["y"], rect["width"], rect["height"]) for rect in absolute_rectangles(back))
        self.assertEqual(mirror, actual)

    def test_kle_offsets_and_alignment(self):
        keys = parse_physical_kle([[{"a": 7}, "Tab"], [{"y": .25}, "b"], ["c"]])["keys"]
        self.assertEqual([0, 1.25, 2.25], [key["y"] for key in keys])
        self.assertEqual("Tab", keys[0]["labels"][4])
        self.assertEqual(1, len(parse_physical_kle([{}, ["x"]])["keys"]))

    def test_fail_closed_for_unsupported_or_invalid_geometry(self):
        for source in ([["a", {"x": -.5}, "b"]], [[{"r": 10}, "a"]],
                       [[{"a": 7}, "a\nb"]], [[{"w2": 0}, "a"]], [[{"h2": -1}, "a"]]):
            with self.assertRaises(ValueError):
                parse_physical_kle(source)

    def test_html_annotations_do_not_eat_literal_ascii(self):
        self.assertEqual("ĉ", plain("c&#770;"))
        self.assertEqual("o\u0305", plain("<span class='cd'>o&#773;</span>"))
        for char in "<>&":
            self.assertEqual(char, plain(char))

    def test_explicit_layers_never_infer_ansi_shift(self):
        keys = build()["keys"]
        ids = {identifier: key for key in keys for identifier in key["yinyuanIds"]}
        for base, shifted, ascii_base, ascii_shift in (
            ("M28", "M25", "[", "{"), ("M29", "M26", "\\", "|"),
            ("M30", "M27", "]", "}"), ("M16", "R04", "E", "@"),
            ("M10", "R10", "A", "Q"), ("M31", "R07", "<", "("),
        ):
            key = ids[base]
            self.assertIs(key, ids[shifted])
            self.assertEqual({"type": "input", "ascii": ascii_base}, key["action"])
            self.assertEqual({"type": "input", "ascii": ascii_shift}, key["shiftAction"])
            self.assertEqual([base], key["baseYinyuanIds"])
            self.assertEqual([shifted], key["shiftYinyuanIds"])
        self.assertNotIn("shiftAction", ids["N12"])
        self.assertNotIn("shiftAction", ids["M01"])
        for key in keys:
            if key["zone"] == "main" and key["action"].get("ascii", "") in "1234567890" and key["action"].get("ascii"):
                self.assertNotIn("shiftAction", key)
                self.assertEqual("input", key["action"]["type"])

    def test_two_independent_numeric_zones_and_ten_edit_actions(self):
        board = build()
        sides = {}
        for zone in ("left", "right"):
            keys = [key for key in board["keys"] if key["zone"] == zone]
            self.assertEqual(18, len(keys))
            self.assertEqual(1, sum(key["action"]["type"] == "toggle-number" for key in keys))
            literal = {key["action"]["ascii"]: key for key in keys if key["action"]["type"] == "literal"}
            self.assertEqual(set("0123456789./*-+"), set(literal))
            self.assertEqual({"type": "noop"}, literal["5"]["editAction"])
            edit = {key["editAction"]["key"] for key in literal.values() if key["editAction"]["type"] == "local"}
            self.assertEqual({"Home", "End", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
                              "PageUp", "PageDown", "Insert", "Delete"}, edit)
            self.assertEqual(1, sum(key["action"] == {"type": "confirm", "key": "Enter"} for key in keys))
            self.assertEqual(1, sum(key["action"] == {"type": "backspace"} for key in keys))
            sides[zone] = [(key["y"], key["width"], key["height"], key["action"], key.get("editAction")) for key in keys]
        self.assertEqual(sides["left"], sides["right"])

    def test_space_modes_caps_and_reused_erhua_aliases(self):
        layout = build()
        actions = [key["action"] for key in layout["keys"]]
        self.assertEqual(2, actions.count({"type": "confirm", "key": "Space"}))
        self.assertEqual(1, actions.count({"type": "toggle-language"}))
        self.assertEqual(1, actions.count({"type": "toggle-punctuation"}))
        self.assertEqual(1, actions.count({"type": "unsupported", "label": "Caps Lock"}))
        self.assertEqual({"R01": "M22", "R02": "M23", "R03": "M24"}, layout["inputIdAliases"])
        for key in layout["keys"]:
            if key.get("inputIdAliases"):
                self.assertTrue(any("/R0" in label for label in key["displayLabels"]))


if __name__ == "__main__":
    unittest.main()
