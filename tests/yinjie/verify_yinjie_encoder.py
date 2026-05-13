import unittest
import json
import tempfile
from pathlib import Path

from syllable.codec.yinjie_encoder import (
    YinjieEncoder,
    YinjieEncodingError,
)
from syllable.analysis.slice.syllable_categorizer import SyllableCategorizer
from syllable.analysis.slice.syllable_encoding_pipeline import SyllableEncodingPipeline
from syllable.analysis.slice.ganyin_categorizer import GanyinCategorizer
from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder
from syllable.analysis.slice.ganyin_encoder import GanyinEncoder
from syllable.analysis.slice.syllable_splitter import SyllableSplitter


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
            "yu3": ("ɥ", "ü3"),
            "yue4": ("ɥ", "üe4"),
            "yuan2": ("ɥ", "üan2"),
            "yun2": ("ɥ", "ün2"),
            "ya1": ("y", "ia1"),
            "ye1": ("y", "ie1"),
            "yo1": ("y", "io1"),
            "you2": ("y", "iou2"),
            "yong1": ("ɥ", "iong1"),
            "jiu2": ("j", "iou2"),
            "dui4": ("d", "uei4"),
            "sun1": ("s", "uen1"),
            "wu3": ("w", "u3"),
            "wa1": ("w", "ua1"),
            "wo1": ("w", "uo1"),
            "wai4": ("w", "uai4"),
            "wei2": ("w", "uei2"),
            "wan1": ("w", "uan1"),
            "wen1": ("w", "uen1"),
            "wang3": ("w", "uang3"),
            "weng1": ("w", "ueng1"),
            "wong4": ("w", "ong4"),
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
            "yǔ": ("ɥ", "ü3"),
            "yā": ("y", "ia1"),
            "yē": ("y", "ie1"),
            "yō": ("y", "io1"),
            "yóu": ("y", "iou2"),
            "yōng": ("ɥ", "iong1"),
            "jiú": ("j", "iou2"),
            "duì": ("d", "uei4"),
            "sūn": ("s", "uen1"),
            "wǔ": ("w", "u3"),
            "wā": ("w", "ua1"),
            "wō": ("w", "uo1"),
            "wài": ("w", "uai4"),
            "wéi": ("w", "uei2"),
            "wān": ("w", "uan1"),
            "wēn": ("w", "uen1"),
            "wǎng": ("w", "uang3"),
            "wēng": ("w", "ueng1"),
            "wòng": ("w", "ong4"),
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

    def test_splitter_uses_umlaut_placeholder_for_yu_family(self):
        cases = {
            "yu3": ("ɥ", "ü3"),
            "yǔ": ("ɥ", "ǔ"),
            "yue4": ("ɥ", "üe4"),
            "yuè": ("ɥ", "üè"),
            "juan4": ("j", "üan4"),
            "juàn": ("j", "üàn"),
            "yong1": ("ɥ", "iong1"),
            "yōng": ("ɥ", "iōng"),
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableSplitter.split_syllable(syllable), expected)

    def test_splitter_restores_standard_finals_for_non_umlaut_y_families(self):
        cases = {
            "ya1": ("y", "ia1"),
            "yā": ("y", "iā"),
            "yan2": ("y", "ian2"),
            "yán": ("y", "ián"),
            "yang3": ("y", "iang3"),
            "yǎng": ("y", "iǎng"),
            "yao4": ("y", "iao4"),
            "yào": ("y", "iào"),
            "ye1": ("y", "ie1"),
            "yē": ("y", "iē"),
            "yo1": ("y", "io1"),
            "yō": ("y", "iō"),
            "you2": ("y", "iou2"),
            "yóu": ("y", "ióu"),
            "yi1": ("y", "i1"),
            "yī": ("y", "ī"),
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableSplitter.split_syllable(syllable), expected)

    def test_splitter_restores_standard_finals_for_standard_w_families(self):
        cases = {
            "wu3": ("w", "u3"),
            "wǔ": ("w", "ǔ"),
            "wa1": ("w", "ua1"),
            "wā": ("w", "uā"),
            "wo1": ("w", "uo1"),
            "wō": ("w", "uō"),
            "wai4": ("w", "uai4"),
            "wài": ("w", "uài"),
            "wei2": ("w", "uei2"),
            "wéi": ("w", "uéi"),
            "wan1": ("w", "uan1"),
            "wān": ("w", "uān"),
            "wen1": ("w", "uen1"),
            "wēn": ("w", "uēn"),
            "wang3": ("w", "uang3"),
            "wǎng": ("w", "uǎng"),
            "weng1": ("w", "ueng1"),
            "wēng": ("w", "uēng"),
            "wong4": ("w", "ong4"),
            "wòng": ("w", "òng"),
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableSplitter.split_syllable(syllable), expected)

    def test_splitter_restores_standard_finals_for_generic_abbreviations(self):
        cases = {
            "jiu2": ("j", "iou2"),
            "jiú": ("j", "ióu"),
            "qiu1": ("q", "iou1"),
            "qiū": ("q", "iōu"),
            "dui4": ("d", "uei4"),
            "duì": ("d", "uèi"),
            "zhui1": ("zh", "uei1"),
            "zhuī": ("zh", "uēi"),
            "sun1": ("s", "uen1"),
            "sūn": ("s", "uēn"),
            "chun2": ("ch", "uen2"),
            "chún": ("ch", "uén"),
        }

        for syllable, expected in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableSplitter.split_syllable(syllable), expected)


class TestYinjieEncoder(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        encoder = YinjieEncoder()
        cls.project_root = encoder.project_root
        # 加载所有拼音音节
        with open(cls.project_root / 'internal_data' / 'pinyin_source_db' / 'lexicon_exports' / 'pinyin_normalized.json', 'r', encoding='utf-8') as f:
            cls.all_pinyin = list(json.load(f).keys())
        cls.encoder = encoder
        cls.shouyin_encoder = ShouyinEncoder()
        cls.ganyin_encoder = GanyinEncoder()

    def test_default_output_path_is_package_file(self):
        """默认输出路径应统一落到 syllable/codec/yinjie_code.json。"""
        self.assertEqual(
            self.encoder._get_output_path("yinyuan"),
            self.encoder.project_root / "syllable" / "codec" / "yinjie_code.json",
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

    def test_yu_family_internal_placeholder_reuses_y_runtime_slot(self):
        cases = {
            "yu3": ("ɥ", "ü3"),
            "yue4": ("ɥ", "üe4"),
            "yuan2": ("ɥ", "üan2"),
            "yun2": ("ɥ", "ün2"),
            "yong1": ("ɥ", "iong1"),
        }

        y_runtime = self.shouyin_encoder.encode_shouyin("y")
        placeholder_runtime = self.shouyin_encoder.encode_shouyin("ɥ")
        self.assertEqual(placeholder_runtime, y_runtime)

        for syllable, expected_parts in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableCategorizer.analyze_syllable(syllable), expected_parts)

                expected_code = (
                    placeholder_runtime
                    + self.ganyin_encoder.encode_ganyin(expected_parts[1])
                )
                self.assertEqual(self.encoder.encode_single_yinjie(syllable), expected_code)

    def test_y_family_standard_finals_encode_with_restored_i_families(self):
        cases = {
            "ya1": ("y", "ia1"),
            "yan2": ("y", "ian2"),
            "yang3": ("y", "iang3"),
            "yao4": ("y", "iao4"),
            "ye1": ("y", "ie1"),
            "yo1": ("y", "io1"),
            "you2": ("y", "iou2"),
            "yi1": ("y", "i1"),
        }

        y_runtime = self.shouyin_encoder.encode_shouyin("y")

        for syllable, expected_parts in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableCategorizer.analyze_syllable(syllable), expected_parts)
                expected_code = y_runtime + self.ganyin_encoder.encode_ganyin(expected_parts[1])
                self.assertEqual(self.encoder.encode_single_yinjie(syllable), expected_code)

    def test_w_family_standard_finals_encode_with_restored_u_families(self):
        cases = {
            "wu3": ("w", "u3"),
            "wa1": ("w", "ua1"),
            "wo1": ("w", "uo1"),
            "wai4": ("w", "uai4"),
            "wei2": ("w", "uei2"),
            "wan1": ("w", "uan1"),
            "wen1": ("w", "uen1"),
            "wang3": ("w", "uang3"),
            "weng1": ("w", "ueng1"),
            "wong4": ("w", "ong4"),
        }

        w_runtime = self.shouyin_encoder.encode_shouyin("w")

        for syllable, expected_parts in cases.items():
            with self.subTest(syllable=syllable):
                self.assertEqual(SyllableCategorizer.analyze_syllable(syllable), expected_parts)
                expected_code = w_runtime + self.ganyin_encoder.encode_ganyin(expected_parts[1])
                self.assertEqual(self.encoder.encode_single_yinjie(syllable), expected_code)

    def test_generic_abbreviated_finals_encode_with_standard_forms(self):
        cases = {
            "jiu2": ("j", "iou2"),
            "qiu1": ("q", "iou1"),
            "dui4": ("d", "uei4"),
            "zhui1": ("zh", "uei1"),
            "sun1": ("s", "uen1"),
            "run4": ("r", "uen4"),
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
