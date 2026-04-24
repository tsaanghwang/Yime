import unittest
from pathlib import Path

from yinjie import Yinjie
from yinjie_decoder import YinjieDecoder, YinjieDecoderRunResult


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

            def save_phoneme_dict(self, output_file="phoneme_dict.json", decoded_map=None):
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

            def save_phoneme_dict(self, output_file="phoneme_dict.json", decoded_map=None):
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


if __name__ == "__main__":
    unittest.main()
