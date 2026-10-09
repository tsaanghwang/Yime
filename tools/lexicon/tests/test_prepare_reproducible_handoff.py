from __future__ import annotations

import sys
import hashlib
import tempfile
import unittest
from pathlib import Path


LEXICON_TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LEXICON_TOOLS))

from prepare_reproducible_handoff import (
    SOURCE_ARTIFACTS, TRIAL_DECISIONS, VerificationError, _write_json, prepare,
)


class ReproducibleHandoffWriterTests(unittest.TestCase):
    def test_json_evidence_uses_repository_lf_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "evidence.json"
            _write_json(output, {"value": [1, 2]})

            payload = output.read_bytes()
            self.assertNotIn(b"\r\n", payload)
            self.assertTrue(payload.endswith(b"\n"))

    def _rebuild_fixture(self, root: Path) -> dict:
        dictionary = b"test dictionary\n"
        selection = b"test selection\n"
        runtime = root / "source.db"
        runtime.write_bytes(b"locked test source")
        record = {
            "output_sha256": hashlib.sha256(dictionary).hexdigest(),
            "selection_tsv_sha256": hashlib.sha256(selection).hexdigest(),
            "total_reading_entries": 1, "total_distinct_texts": 1,
            "distinct_texts_by_length": {"1": 1}, "reading_entries_by_length": {"1": 1},
            "single_character_ranking": {},
            "ranking_evidence": {
                "policy_id": "test", "policy_sha256": "test",
                "distinct_texts_by_source": {}, "missing_selected_source_texts": 0,
                "raw_bcc_and_lmdg_values_added": False,
            },
        }
        for run in ("a", "b"):
            source = root / ("source-" + run)
            trial = root / ("trial-" + run)
            source.mkdir()
            trial.mkdir()
            for artifact in SOURCE_ARTIFACTS:
                (source / artifact).write_bytes(b"source evidence\n")
            _write_json(source / "manifest.json", {"counts": {}, "source_gate_counts": {}})
            _write_json(trial / "manifest.json", {
                **{name: {"decision": "pass"} for name in TRIAL_DECISIONS},
                "dictionary": record,
            })
            (trial / "two_level_full.dict.yaml").write_bytes(dictionary)
            (trial / "selection.tsv").write_bytes(selection)
        return {
            "source_a": root / "source-a", "source_b": root / "source-b",
            "trial_a": root / "trial-a", "trial_b": root / "trial-b",
            "runtime_database": runtime,
            "expected_runtime_sha256": hashlib.sha256(runtime.read_bytes()).hexdigest(),
            "source_date_epoch": 1,
        }

    def test_candidate_evidence_does_not_claim_release_approval(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = self._rebuild_fixture(Path(temporary))
            evidence, report = prepare(**args, candidate_only=True)
            self.assertEqual(evidence["status"], "prepared_handoff_candidate")
            self.assertEqual(report["decision"], "pass")
            self.assertEqual(report["clean_rebuild_count"], 2)
            self.assertIn("promotion remain separate", evidence["provenance"]["note"])

    def test_candidate_flag_does_not_bypass_two_build_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = self._rebuild_fixture(Path(temporary))
            (args["trial_b"] / "selection.tsv").write_bytes(b"drift\n")
            with self.assertRaisesRegex(VerificationError, "selection SHA-256"):
                prepare(**args, candidate_only=True)


if __name__ == "__main__":
    unittest.main()
