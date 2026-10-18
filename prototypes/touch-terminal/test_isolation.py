"""Prevent lab generators from replacing product projections or protections."""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.generate_ascii_layout import generated_payloads
from tools.ascii_keyboard.layout_chain import load_input_id_to_layout_key
from yime.utils.yinyuan_id_chain import load_yinyuan_id_to_layout_key


class ProductIsolationTests(unittest.TestCase):
    def test_product_and_lab_keep_distinct_projections(self):
        product = load_yinyuan_id_to_layout_key(ROOT)
        lab = load_input_id_to_layout_key(ROOT)
        self.assertEqual(product["N12"], product["N26"])
        self.assertEqual(product["N25"], product["N27"])
        self.assertFalse(set("!@#$%^&*(") & set(product.values()))
        self.assertNotEqual(lab["N12"], lab["N26"])
        self.assertEqual("!", lab["M22"])

    def test_generator_has_only_lab_destinations_and_current_shared_algorithm(self):
        for relative, content in generated_payloads(ROOT).items():
            self.assertTrue(relative.as_posix().startswith((
                "prototypes/touch-terminal/encoding/", "go-backend/internal/asciicodemode/")))
            self.assertEqual(content, (ROOT / relative).read_text(encoding="utf-8"))

    def test_codegen_works_with_windows_legacy_pipe_encoding(self):
        # Reproduce an English Windows subprocess locale independently of the
        # machine running this test. Without explicit UTF-8, the stdin writer
        # raises UnicodeEncodeError and gofmt waits forever for EOF.
        import subprocess
        script = """
from unittest.mock import patch
from tools.generate_ascii_layout import generated_payloads
with patch('locale.getencoding', return_value='cp1252'):
    assert generated_payloads()
print('PASS explicit UTF-8 code generation under legacy locale')
"""
        result = subprocess.run([sys.executable, "-X", "utf8=0", "-c", script],
                                cwd=ROOT, capture_output=True, encoding="utf-8", timeout=40)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
