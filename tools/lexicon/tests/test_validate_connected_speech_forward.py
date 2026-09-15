from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.lexicon import validate_connected_speech_forward as forward


class ConnectedSpeechForwardTests(unittest.TestCase):
    def test_current_repository_forward_chain_is_read_only_and_outcome_only(self) -> None:
        report = forward.validate_forward_sources(forward.REPO_ROOT)
        self.assertTrue(report["passed"])
        self.assertEqual(report["schema_version"], "yimecore-speech-forward-source-v1")
        self.assertEqual(report["record_count"], 24)
        self.assertEqual(report["syllable_count"], 50)
        self.assertEqual(report["record_ids"], list(forward.REVIEW_IDS))
        self.assertTrue(report["checks"]["inputs_unchanged"])
        self.assertTrue(report["checks"]["semantic_tone_substitutions"])
        self.assertFalse(report["checks"]["rime_executed"])
        self.assertFalse(report["checks"]["aliases_generated"])
        self.assertEqual({item["role"] for item in report["inputs"]}, set(forward.SOURCE_PATHS))
        self.assertEqual(set(report["input_sha256"]), set(forward.SOURCE_PATHS.values()))
        for item in report["inputs"]:
            self.assertRegex(item["sha256"], r"^[0-9a-f]{64}$")
            self.assertFalse(Path(item["path"]).is_absolute())
        encoded_report = json.dumps(report, ensure_ascii=False)
        for private_field in ('"text"', '"canonical_pinyin"', '"yinyuan_ids"'):
            self.assertNotIn(private_field, encoded_report)

    def test_missing_inventory_entry_fails_before_encoder(self) -> None:
        original = forward._load_json

        def without_required_syllable(path: Path) -> dict:
            result = original(path)
            if path.name == "pinyin_normalized.json":
                result.pop("ling3")
            return result

        with patch.object(forward, "_load_json", side_effect=without_required_syllable):
            with self.assertRaisesRegex(forward.ForwardValidationError, "syllable_not_in_canonical_inventory"):
                forward.validate_forward_sources(forward.REPO_ROOT)

    def test_packaged_layout_drift_fails(self) -> None:
        original = forward._load_json

        def changed_layout(path: Path) -> dict:
            result = original(path)
            if path.name == "yime_yinyuan_layout.json":
                result["yinyuan_id_to_key"]["N01"] = "!"
            return result

        with patch.object(forward, "_load_json", side_effect=changed_layout):
            with self.assertRaisesRegex(forward.ForwardValidationError, "layout_projection_mismatch"):
                forward.validate_forward_sources(forward.REPO_ROOT)

    def test_unrelated_checkout_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(forward.ForwardValidationError, "repo_must_match_validator_checkout"):
                forward.validate_forward_sources(Path(directory))

    def test_phrase_order_and_missing_source_are_rejected(self) -> None:
        records = [{"text": "测试", "canonical_pinyin": "a3 b3"}]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.tsv"
            source.write_text("phrase\tphrase_len\tcommon_reading\treadings\n测试\t2\tb3 a3\tb3 a3\n", encoding="utf-8")
            with self.assertRaisesRegex(forward.ForwardValidationError, "canonical_phrase_source_mismatch"):
                forward._check_phrase_records(records, source, lambda value: value)
            source.write_text("phrase\tphrase_len\tcommon_reading\treadings\n", encoding="utf-8")
            with self.assertRaisesRegex(forward.ForwardValidationError, "canonical_phrase_source_missing"):
                forward._check_phrase_records(records, source, lambda value: value)

    def test_handwritten_decomposition_tuple_is_rejected(self) -> None:
        rows = [{"pinyin_tone": "a3", "shouyin_id": "N01", "huyin_id": "M01", "zhuyin_id": "M02", "moyin_id": "M03"}]
        with self.assertRaisesRegex(forward.ForwardValidationError, "formal_decomposition_mismatch"):
            forward._check_decomposition(rows, {"a3"}, {"a3": ("N12", "M01", "M02", "M03")}, {"a3": "ǎ"}, {})

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with self.assertRaisesRegex(forward.ForwardValidationError, "duplicate_json_key"):
            json.loads('{"a": 1, "a": 2}', object_pairs_hook=forward._reject_duplicate_keys)

    def semantic_fixture(self) -> tuple[list[dict], dict, dict]:
        rows = [{"canonical_pinyin": "a3 b3", "expected_surface_pinyin": "a2 b3"}]
        encoded = {
            "a3": ("initial", "quality-a-low", "quality-b-low", "quality-c-low"),
            "a2": ("initial", "quality-a-low", "quality-b-mid", "quality-c-high"),
            "b3": ("other-initial", "quality-c-low", "quality-b-low", "quality-a-low"),
        }
        registry = {
            "initial": {"category": "initial", "semantic_code": "INITIAL_A"},
            "other-initial": {"category": "initial", "semantic_code": "INITIAL_B"},
        }
        for quality, grade in (("a", "low"), ("b", "low"), ("c", "low"), ("b", "mid"), ("c", "high")):
            registry[f"quality-{quality}-{grade}"] = {
                "category": "musical", "semantic_code": f"YPY_{quality.upper()}_{grade.upper()}",
            }
        return rows, encoded, registry

    def test_semantic_substitution_uses_attributes_not_numbered_ids(self) -> None:
        self.assertEqual(forward._check_semantic_tone_substitutions(*self.semantic_fixture()), 1)

    def test_semantic_substitution_rejects_quality_or_grade_changes(self) -> None:
        for replacement, error in (
            ("YPY_C_MID", "semantic_musical_quality_changed"),
            ("YPY_B_HIGH", "semantic_tone_grade_mismatch"),
            ("not-declared", "musical_semantic_attributes_missing"),
        ):
            with self.subTest(replacement=replacement):
                rows, encoded, registry = self.semantic_fixture()
                registry["quality-b-mid"]["semantic_code"] = replacement
                with self.assertRaisesRegex(forward.ForwardValidationError, error):
                    forward._check_semantic_tone_substitutions(rows, encoded, registry)
        rows, encoded, registry = self.semantic_fixture()
        registry["quality-b-low"]["semantic_code"] = "YPY_B_MID"
        with self.assertRaisesRegex(forward.ForwardValidationError, "semantic_tone_grade_mismatch"):
            forward._check_semantic_tone_substitutions(rows, encoded, registry)

    def test_semantic_substitution_preserves_initial_and_second_syllable(self) -> None:
        rows, encoded, registry = self.semantic_fixture()
        encoded["a2"] = ("other-initial", *encoded["a2"][1:])
        with self.assertRaisesRegex(forward.ForwardValidationError, "semantic_initial_changed"):
            forward._check_semantic_tone_substitutions(rows, encoded, registry)
        rows, encoded, registry = self.semantic_fixture()
        rows[0]["expected_surface_pinyin"] = "a2 b2"
        encoded["b2"] = encoded["b3"]
        with self.assertRaisesRegex(forward.ForwardValidationError, "reviewed_tone_substitution_scope_mismatch"):
            forward._check_semantic_tone_substitutions(rows, encoded, registry)

    def test_output_must_be_fresh_exact_scoped_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / ".tmp/yimecore-experiment/speech-admission-unittest-1234/forward-source.json"
            self.assertEqual(forward.reserve_output(root, output), output)
            self.assertTrue(output.parent.is_dir())
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(forward.ForwardValidationError, "output_directory_must_be_new"):
                forward.reserve_output(root, output)
            for invalid in (
                root / "forward-source.json",
                root / ".tmp/yimecore-experiment/speech-admission-unittest-1235/private.txt",
                root / ".tmp/yimecore-experiment/other-unittest-1234/forward-source.json",
                root / ".tmp/yimecore-experiment/speech-admission-unittest-1235/nested/forward-source.json",
            ):
                with self.assertRaises(forward.ForwardValidationError):
                    forward.reserve_output(root, invalid)


if __name__ == "__main__":
    unittest.main()
