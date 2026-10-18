from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


LEXICON_TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LEXICON_TOOLS))

from prepare_reproducible_handoff import _write_json


class ReproducibleHandoffWriterTests(unittest.TestCase):
    def test_json_evidence_uses_repository_lf_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "evidence.json"
            _write_json(output, {"value": [1, 2]})

            payload = output.read_bytes()
            self.assertNotIn(b"\r\n", payload)
            self.assertTrue(payload.endswith(b"\n"))


if __name__ == "__main__":
    unittest.main()
