from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_psc_erhua_pdf import is_rule_row, normalize_rule, parse_rule


class ErhuaImportTests(unittest.TestCase):
    def test_rule_normalization_removes_watermark_and_fullwidth_symbols(self) -> None:
        raw, normalized = normalize_rule("畅\nang＞ar（鼻化）")
        self.assertEqual(raw, "ang＞ar（鼻化）")
        self.assertEqual(normalized, "ang>ar(鼻化)")

    def test_rule_parser_preserves_internal_colon(self) -> None:
        self.assertEqual(parse_rule("in>i:er"), ("in", "i:er", False))
        self.assertEqual(parse_rule("ang>ar(鼻化)"), ("ang", "ar", True))
        self.assertEqual(parse_rule("ao:aor"), ("ao", "aor", False))

    def test_rule_row_requires_only_the_first_cell(self) -> None:
        self.assertTrue(is_rule_row(["a＞ar", None, None, None]))
        self.assertFalse(is_rule_row(["板擦儿", "bǎncār", None, None]))


if __name__ == "__main__":
    unittest.main()
