import unittest
import json
import tempfile
from pathlib import Path
from yinjie_encoder import YinjieEncoder
from syllable.analysis.slice.syllable_categorizer import SyllableCategorizer
from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder
from syllable.analysis.slice.ganyin_encoder import GanyinEncoder

class TestYinjieEncoderLength(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 加载所有拼音音节
        with open('pinyin/hanzi_pinyin/pinyin_normalized.json', 'r', encoding='utf-8') as f:
            cls.all_pinyin = list(json.load(f).keys())
        cls.encoder = YinjieEncoder()
        cls.shouyin_encoder = ShouyinEncoder()
        cls.ganyin_encoder = GanyinEncoder()

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
        """hm/hn/hng 通过切分规则进入 सामान्य首音+干音编码路径。"""
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

            with self.assertRaisesRegex(ValueError, r"bad1: 模拟失败"):
                encoder.encode_all_yinjie()

            self.assertFalse((output_dir / "yinjie_code.json").exists())

if __name__ == '__main__':
    unittest.main()
