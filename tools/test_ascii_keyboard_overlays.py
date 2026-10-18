"""Small deterministic tests; no external corpus or installed runtime involved."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.ascii_keyboard_overlays import dictionary_rows, merge_overlay, prepare_inputs, preserve_base_manifest

ROOT = Path(__file__).resolve().parents[1]


class OverlayTests(unittest.TestCase):
    def test_base_manifest_is_verified_and_not_left_as_final_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            data = output / "data"
            data.mkdir()
            hashes = {}
            for mode in ("full", "variable", "shorthand"):
                name = f"yime_{mode}.dict.yaml"
                payload = f"---\n...\n{mode}\tcode\t1\n".encode()
                (data / name).write_bytes(payload)
                hashes[name] = hashlib.sha256(payload).hexdigest()
            source = data / "yime_lexicon_manifest.json"
            source.write_text(json.dumps({"output_sha256": hashes}), encoding="utf-8")
            before = source.read_bytes()
            dictionary = data / "yime_full.dict.yaml"
            dictionary.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                preserve_base_manifest(data, output)
            self.assertTrue(source.is_file())
            dictionary.write_bytes(b"---\n...\nfull\tcode\t1\n")
            result = preserve_base_manifest(data, output)
            self.assertFalse(source.exists())
            self.assertEqual((output / result["path"]).read_bytes(), before)
            self.assertEqual(result["scope"], "canonical_base_before_reviewed_overlays")

    def test_merge_preserves_core_weights_and_audits_collisions(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            core, layer = directory / "core", directory / "layer"
            core.write_text("---\n...\n甲\tn #\t100\n乙\tb@\t80\n", encoding="utf-8")
            layer.write_text("---\n...\n甲\tn#\t1\n丙\tn#\t1\n丁\tz~\t1\n", encoding="utf-8")
            result = merge_overlay(core, [layer])
            self.assertEqual(result["already_in_core"], 1)
            self.assertEqual(result["appended_pairs"], 2)
            self.assertEqual(result["core_collision_buckets"], {"n#": ["甲"]})
            self.assertEqual(len(list(dictionary_rows(core))), 4)
            self.assertIn(("甲", "n#", "100"), list(dictionary_rows(core)))

    def test_nonreviewed_weight_rejected_before_core_write(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            core, layer = directory / "core", directory / "layer"
            core.write_text("---\n...\n甲\tn#\t100\n", encoding="utf-8")
            before = core.read_bytes()
            layer.write_text("---\n...\n乙\tb@\t900\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                merge_overlay(core, [layer])
            self.assertEqual(before, core.read_bytes())

    def test_projection_preserves_reviewed_semantics_and_sources(self):
        source = ROOT / "docs/project/connected_speech/erhua_sound_key_projection.json"
        before = source.read_bytes()
        with tempfile.TemporaryDirectory() as temp:
            generated = json.loads(prepare_inputs(ROOT, Path(temp)).read_text(encoding="utf-8"))
            original = json.loads(before)
            self.assertEqual(generated["sound_units"], original["sound_units"])
            self.assertEqual(generated["invariants"], original["invariants"])
            self.assertFalse(generated["runtime_enabled"])
            dedicated = [item["layout_key"] for item in generated["key_classes"] if "layout_key" in item]
            self.assertEqual(len(dedicated), 15)
            self.assertEqual(len(set(dedicated)), 15)
            self.assertEqual(len((Path(temp)/"yime_pinyin_codes.tsv").read_text(encoding="utf-8").splitlines()), 1738)
        self.assertEqual(before, source.read_bytes())


if __name__ == "__main__":
    unittest.main()
