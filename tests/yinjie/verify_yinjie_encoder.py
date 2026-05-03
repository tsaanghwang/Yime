import unittest
import json
import tempfile
from pathlib import Path

from syllable_codec.yinjie_encoder import (
    YinjieEncoder,
    YinjieEncodingError,
)
from syllable.analysis.slice.syllable_categorizer import SyllableCategorizer
from syllable.analysis.slice.syllable_encoding_pipeline import SyllableEncodingPipeline
from syllable.analysis.slice.ganyin_categorizer import GanyinCategorizer
from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder
from syllable.analysis.slice.ganyin_encoder import GanyinEncoder


class TestSyllableEncodingPipeline(unittest.TestCase):
    def test_normalize_tone_mark_to_number(self):
        cases = {
            "zhōng": "zhong1",
            "ḿ": "m2",
            "ǹg": "ng4",
            "xue2": "xue2",
            "": "",
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableEncodingPipeline.normalize_syllable(syllable), expected)

    def test_split_normalized_syllable_handles_encoding_special_cases(self):
        cases = {
            "hm1": ("h", "m1"),
            "hn2": ("h", "n2"),
            "hng3": ("h", "ng3"),
            "ng5": ("'", "ng5"),
            "ê2": ("'", "ê2"),
            "zhi1": ("zh", "_i1"),
            "xue2": ("x", "üe2"),
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableEncodingPipeline.split_normalized_syllable(syllable), expected)

    def test_pipeline_matches_legacy_categorizer_behavior(self):
        cases = {
            "hm1": ("h", "m1"),
            "hng3": ("h", "ng3"),
            "zhōng": ("zh", "ong1"),
            "xue2": ("x", "üe2"),
            "ng5": ("'", "ng5"),
        }

        for syllable, expected_parts in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableEncodingPipeline.analyze_syllable(syllable), expected_parts)
                self.assertEqual(SyllableCategorizer.analyze_syllable(syllable), expected_parts)
                self.assertEqual(
                    SyllableEncodingPipeline.analyze_syllable(syllable),
                    SyllableCategorizer.analyze_syllable(syllable),
                )

    def test_legacy_categorizer_keeps_shouyin_generation_compatibility(self):
        pinyin_data = {
            "ma1": "mā",
            "xue2": "xué",
            "ai1": "āi",
        }

        self.assertEqual(
            SyllableCategorizer.generate_shouyin_data(pinyin_data),
            GanyinCategorizer.generate_shouyin_data(pinyin_data),
        )


class TestYinjieEncoder(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        encoder = YinjieEncoder()
        cls.project_root = encoder.project_root
        # 加载所有拼音音节
        with open(cls.project_root / 'pinyin' / 'hanzi_pinyin' / 'pinyin_normalized.json', 'r', encoding='utf-8') as f:
            cls.all_pinyin = list(json.load(f).keys())
        cls.encoder = encoder
        cls.shouyin_encoder = ShouyinEncoder()
        cls.ganyin_encoder = GanyinEncoder()

    def test_default_output_path_is_package_file(self):
        """默认输出路径应统一落到 syllable_codec/yinjie_code.json。"""
        self.assertEqual(
            self.encoder._get_output_path("yinyuan"),
            self.encoder.project_root / "syllable_codec" / "yinjie_code.json",
        )

    def test_all_pinyin_length(self):
        """测试所有拼音音节的编码长度不超过4个码位"""
        for pinyin in self.all_pinyin:
            with self.subTest(pinyin=pinyin):
                encoded = self.encoder.encode_single_yinjie(pinyin)
                self.assertLessEqual(
                    len(encoded),
                    4,
                    f"拼音 '{pinyin}' 的编码 '{encoded}' 长度超过4个码位"
                )

    def test_h_nasal_syllables_follow_normal_path(self):
        """hm/hn/hng 通过切分规则进入常规首音+干音编码路径。"""
        cases = {
            "hm1": ("h", "m1"),
            "hn2": ("h", "n2"),
            "hng3": ("h", "ng3"),
        }

        for syllable, expected_parts in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableCategorizer.analyze_syllable(syllable), expected_parts)

                expected_code = (
                    self.shouyin_encoder.encode_shouyin(expected_parts[0])
                    + self.ganyin_encoder.encode_ganyin(expected_parts[1])
                )
                self.assertEqual(self.encoder.encode_single_yinjie(syllable), expected_code)

    def test_encode_all_yinjie_raises_and_skips_output_on_failure(self):
        """批量生成时应汇总失败项，并且失败时不写输出文件。"""

        class ControlledYinjieEncoder(YinjieEncoder):
            def __init__(self, output_dir: Path):
                super().__init__()
                self.output_dir = output_dir

            def _get_input_path(self) -> Path:
                return Path("controlled-input.json")

            def _get_output_path(self, subdir: str) -> Path:
                return self.output_dir / "yinjie_code.json"

            def _load_json(self, path: Path):
                return {"ma1": "mā", "bad1": "bad"}

            def encode_single_yinjie(self, syllable: str) -> str:
                if syllable == "bad1":
                    raise ValueError("模拟失败")
                return "ok"

        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)
            encoder = ControlledYinjieEncoder(output_dir)

            with self.assertRaisesRegex(YinjieEncodingError, r"bad1: 模拟失败"):
                encoder.encode_all_yinjie()

            self.assertFalse((output_dir / "yinjie_code.json").exists())

if __name__ == '__main__':
    unittest.main()
