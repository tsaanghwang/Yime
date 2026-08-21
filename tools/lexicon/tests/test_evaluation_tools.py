from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.evaluation.compare_layout import compare_layouts, validate_candidate_shape
from tools.evaluation.context import REPO_ROOT, file_sha256
from tools.evaluation.evaluate_modes import summarize_dictionary


class EvaluationToolTests(unittest.TestCase):
    def test_dictionary_summary_uses_packaged_rime_codes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            dictionary = Path(temp) / "fixture.dict.yaml"
            dictionary.write_text(
                "---\nname: fixture\n...\n甲\tab\t2\n乙\tab\t1\n丙\tZ\t1\n",
                encoding="utf-8",
            )
            summary = summarize_dictionary(dictionary)
        self.assertEqual(summary["entry_count"], 3)
        self.assertEqual(summary["distinct_codes"], 2)
        self.assertEqual(summary["collision_bucket_count"], 1)
        self.assertEqual(summary["entries_in_collision_buckets"], 2)
        self.assertGreater(
            summary["mean_modifier_adjusted_presses"],
            summary["mean_code_length"],
        )

    def test_canonical_layout_is_a_zero_delta_read_only_trial(self) -> None:
        canonical = REPO_ROOT / "internal_data" / "manual_key_layout.json"
        before = file_sha256(canonical)
        report, patch = compare_layouts(canonical)
        self.assertEqual(report["candidate_layout"]["changed_slot_count"], 0)
        self.assertTrue(all(value == 0.0 for value in report["delta"].values()))
        self.assertFalse(report["canonical_layout_written"])
        self.assertEqual(patch["changes"], [])
        self.assertEqual(file_sha256(canonical), before)

    def test_layout_trial_outputs_assignment_patch_without_writeback(self) -> None:
        canonical = REPO_ROOT / "internal_data" / "manual_key_layout.json"
        payload = json.loads(canonical.read_text(encoding="utf-8"))
        first = next(
            item for item in payload["layers"] if item.get("yinyuan_id") == "N01"
        )
        second = next(
            item for item in payload["layers"] if item.get("yinyuan_id") == "N10"
        )
        first["yinyuan_id"], second["yinyuan_id"] = (
            second["yinyuan_id"],
            first["yinyuan_id"],
        )
        before = file_sha256(canonical)
        with tempfile.TemporaryDirectory() as temp:
            candidate = Path(temp) / "candidate.json"
            candidate.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            report, patch = compare_layouts(candidate)
        self.assertEqual(report["candidate_layout"]["changed_slot_count"], 2)
        self.assertEqual(len(patch["changes"]), 2)
        self.assertFalse(report["canonical_layout_written"])
        self.assertEqual(file_sha256(canonical), before)

    def test_layout_trial_rejects_non_assignment_edits(self) -> None:
        canonical_path = REPO_ROOT / "internal_data" / "manual_key_layout.json"
        canonical = json.loads(canonical_path.read_text(encoding="utf-8"))
        candidate = json.loads(canonical_path.read_text(encoding="utf-8"))
        candidate["metadata"]["name"] = "parallel layout source"
        with self.assertRaisesRegex(ValueError, "metadata"):
            validate_candidate_shape(candidate, canonical)


if __name__ == "__main__":
    unittest.main()
