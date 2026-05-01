import unittest
import json
import tempfile
from pathlib import Path

from yinjie import Yinjie
from yinjie_decoder import DEFAULT_PHONEME_REPORT, YinjieDecoder, YinjieDecoderRunResult


class TestYinjieDecoderRunContract(unittest.TestCase):
    def test_run_decodes_all_only_once_and_reuses_same_map(self):
        decoded_map = {
            "ma1": Yinjie(initial="A", ascender="B", peak="C", descender="D"),
            "ni3": Yinjie(initial="E", ascender="F", peak="G", descender="H"),
        }

        class ControlledYinjieDecoder(YinjieDecoder):
            def __init__(self):
                self.decode_all_calls = 0
                self.save_calls = []
                self.show_calls = []
                self.map_calls = []

            def decode_all(self):
                self.decode_all_calls += 1
                return decoded_map

            def save_phoneme_dict(self, output_file=DEFAULT_PHONEME_REPORT, decoded_map=None):
                self.save_calls.append((output_file, decoded_map))
                return Path(output_file)

            def show_examples(self, examples, decoded_map=None):
                self.show_calls.append((examples, decoded_map))

            def map_key_to_code(self, output_file="key_to_code.json", decoded_map=None):
                self.map_calls.append((output_file, decoded_map))
                return {"N01": "A"}

        decoder = ControlledYinjieDecoder()

        result = decoder.run(
            phoneme_output="phoneme.json",
            key_output="keys.json",
            examples=["ma1"],
        )

        self.assertEqual(decoder.decode_all_calls, 1)
        self.assertEqual(decoder.save_calls, [("phoneme.json", decoded_map)])
        self.assertEqual(decoder.show_calls, [(["ma1"], decoded_map)])
        self.assertEqual(decoder.map_calls, [("keys.json", decoded_map)])
        self.assertIsInstance(result, YinjieDecoderRunResult)
        self.assertEqual(result.decoded_count, 2)
        self.assertEqual(result.phoneme_dict_path, Path("phoneme.json"))
        self.assertEqual(result.key_to_code_path, Path("keys.json"))

    def test_run_skips_example_output_when_examples_not_provided(self):
        decoded_map = {
            "ma1": Yinjie(initial="A", ascender="B", peak="C", descender="D"),
        }

        class ControlledYinjieDecoder(YinjieDecoder):
            def __init__(self):
                self.decode_all_calls = 0
                self.show_calls = 0

            def decode_all(self):
                self.decode_all_calls += 1
                return decoded_map

            def save_phoneme_dict(self, output_file=DEFAULT_PHONEME_REPORT, decoded_map=None):
                return Path(output_file)

            def show_examples(self, examples, decoded_map=None):
                self.show_calls += 1

            def map_key_to_code(self, output_file="key_to_code.json", decoded_map=None):
                return {"N01": "A"}

        decoder = ControlledYinjieDecoder()

        result = decoder.run()

        self.assertEqual(decoder.decode_all_calls, 1)
        self.assertEqual(decoder.show_calls, 0)
        self.assertEqual(result.decoded_count, 1)


class TestYinjieDecoderKeyToCodeGeneration(unittest.TestCase):
    def test_map_key_to_code_uses_layout_slots_from_sources(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            code_file = temp_root / "yinjie_code.json"
            code_file.write_text("{}", encoding="utf-8")

            shouyin_source = temp_root / "zaoyin_yinyuan_enhanced.json"
            shouyin_source.write_text(
                json.dumps(
                    {
                        "entries": {
                            "y": {"layout_slot": "N23", "runtime_char": "Y"},
                            "w": {"layout_slot": "N24", "runtime_char": "W"},
                        }
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            yueyin_source = temp_root / "yueyin_yinyuan_enhanced.json"
            yueyin_source.write_text(
                json.dumps(
                    {
                        "entries": {
                            "tone_a": {"layout_slot": "M01", "runtime_char": "A"},
                            "tone_b": {"layout_slot": "M02", "runtime_char": "B"},
                        }
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            class ControlledYinjieDecoder(YinjieDecoder):
                def _get_shouyin_source_path(self) -> Path:
                    return shouyin_source

                def _get_yueyin_source_path(self) -> Path:
                    return yueyin_source

            decoder = ControlledYinjieDecoder(code_file=code_file)
            result = decoder.map_key_to_code(output_file=temp_root / "key_to_code.json")

            self.assertEqual(result["N23"], "Y")
            self.assertEqual(result["N24"], "W")
            self.assertEqual(result["M01"], "A")
            self.assertEqual(result["M02"], "B")


if __name__ == "__main__":
    unittest.main()
