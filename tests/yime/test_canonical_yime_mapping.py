import unittest

from yime.canonical_yime_mapping import (
    convert_legacy_code_to_primary,
    load_canonical_code_map,
    load_virtual_initial_symbol,
)


class TestCanonicalYimeMapping(unittest.TestCase):
    def test_convert_legacy_code_to_primary_uses_variable_length_yinyuan_rules(self):
        self.assertEqual(
            convert_legacy_code_to_primary("XAAB"),
            "XAB",
        )

    def test_convert_legacy_code_to_primary_handles_short_prefix_compatibly(self):
        self.assertEqual(
            convert_legacy_code_to_primary("XAA"),
            "XA",
        )

    def test_default_virtual_initial_matches_canonical_code_layer(self):
        canonical_code_map = load_canonical_code_map()
        virtual_initial = load_virtual_initial_symbol()
        full_code = canonical_code_map["a1"]

        self.assertTrue(full_code.startswith(virtual_initial))
        self.assertEqual(convert_legacy_code_to_primary(full_code), full_code[:2])


if __name__ == "__main__":
    unittest.main()
