import json
import unittest
from pathlib import Path
from typing import Any, Final, cast

from syllable.analysis.ganyin_encoder import GanyinEncoder
from syllable.analysis.yueyin_mapper import YueyinMapper
from tools.syllable_analysis.ganyin_slicer import GanyinSlicer


SYLLABLE_DIR = Path(__file__).resolve().parents[2] / "syllable"
FINAL_STYLES_PATH = SYLLABLE_DIR / "yinyuan" / "final_styles.json"
GANYIN_ENHANCED_PATH = (
    Path(__file__).resolve().parents[2]
    / "internal_data"
    / "yinyuan_derived"
    / "ganyin_enhanced.json"
)

class TestGanyinEncoder(unittest.TestCase):
    """干音编码器完备测试"""

    @classmethod
    def setUpClass(cls):
        mapping_path = SYLLABLE_DIR / "yinyuan" / "ganyin_to_fixed_length_yinyuan_sequence.json"
        with mapping_path.open('r', encoding='utf-8') as file:
            cls.encoding_map = json.load(file)

        cls.encoder = GanyinEncoder()
        cls.expected_keys = set(cls.encoding_map)
        cls.source_keys = set(cls.encoder.ganyin_part_map)

    def test_encoding_snapshot_matches_source_keys(self):
        """快照文件应完整覆盖当前编码器可处理的全部干音键。"""
        self.assertEqual(self.expected_keys, self.source_keys)

    def test_final_style_ipa_values_are_unpitched_quality_bases(self):
        """final_styles 的 IPA 基形不得混入声调或音高数字。"""
        with FINAL_STYLES_PATH.open("r", encoding="utf-8") as file:
            final_styles = json.load(file)

        entries = {
            final: info
            for category in final_styles["finals"].values()
            for final, info in category.items()
        }
        self.assertEqual(entries["er"]["ipa"], "ɚ")
        for full_final, surface_final in (("iou", "iu"), ("uei", "ui"), ("uen", "un")):
            with self.subTest(full_final=full_final, surface_final=surface_final):
                self.assertIn(full_final, entries)
                self.assertNotIn(surface_final, entries)
        for deferred_final in ("ue", "v", "ve", "van", "vn"):
            with self.subTest(deferred_final=deferred_final):
                self.assertNotIn(deferred_final, entries)
        for final, info in entries.items():
            with self.subTest(final=final):
                ipa = str(info["ipa"])
                self.assertFalse(
                    any(character.isdigit() for character in ipa),
                    f"无调 IPA 基形不得含数字：{final} -> {ipa}",
                )

    def test_materialized_er_ipa_does_not_retain_quality_digit(self):
        """增强视图应只在 ɚ 后附加调值，不得保留历史误混入的 5。"""
        with GANYIN_ENHANCED_PATH.open("r", encoding="utf-8") as file:
            enhanced = json.load(file)

        er_entries = enhanced["single quality ganyin"]
        for key in ("er2", "er3", "er4", "er5"):
            with self.subTest(ganyin=key):
                ipa = str(er_entries[key]["ipa"])
                self.assertTrue(ipa.startswith("ɚ"))
                self.assertNotIn("ɚ5", ipa)

    def test_all_ganyin_encodings_match_snapshot(self):
        """所有干音编码都应与固定快照完全一致。"""
        for ganyin, expected in self.encoding_map.items():
            with self.subTest(ganyin=ganyin):
                result = self.encoder.encode_ganyin(ganyin)
                self.assertEqual(
                    result, expected,
                    f"干音 '{ganyin}' 编码错误: 预期 '{expected}' (U+{ord(expected[0]):04X}...), 实际得到 '{result}'"
                )

    def test_all_snapshot_encodings_are_fixed_length(self):
        """快照中的所有干音编码都应为非空三码。"""
        for ganyin, expected in self.encoding_map.items():
            with self.subTest(ganyin=ganyin):
                self.assertEqual(len(expected), 3)
                self.assertTrue(all(symbol for symbol in expected))

                actual = self.encoder.encode_ganyin(ganyin)
                self.assertEqual(len(actual), 3)

    def test_ong_and_ueng_are_not_premerged(self):
        """ong/ueng 在正式合并规则立项前保持各自的实例驱动查表名。"""
        self.assertEqual(self.encoder.normalize_ganyin_name("ong1"), "ong1")
        self.assertEqual(self.encoder.normalize_ganyin_name("ueng1"), "ueng1")
        self.assertIn("ong1", self.source_keys)
        self.assertIn("ueng1", self.source_keys)
        self.assertFalse(any(key.startswith("uong") for key in self.source_keys))

    def test_h_nasal_aliases_normalize_to_base_ganyin(self):
        """hm/hn/hng 只在对应来源调实际存在时复用 m/n/ng 编码。"""
        alias_pairs = (("hm", "m"), ("hn", "n"), ("hng", "ng"))

        for alias_prefix, base_prefix in alias_pairs:
            for tone in range(1, 6):
                alias = f"{alias_prefix}{tone}"
                base = f"{base_prefix}{tone}"
                with self.subTest(alias=alias, base=base):
                    if base in self.source_keys:
                        self.assertEqual(
                            self.encoder.encode_ganyin(alias),
                            self.encoder.encode_ganyin(base),
                        )
                    else:
                        with self.assertRaises(ValueError):
                            self.encoder.encode_ganyin(alias)

    def test_abbreviated_finals_normalize_to_full_internal_forms(self):
        """iu/ui/un 只作兼容输入，三段分析和编码表统一保存完整韵母。"""
        alias_pairs = (("iu", "iou"), ("ui", "uei"), ("un", "uen"))

        for surface_prefix, full_prefix in alias_pairs:
            for tone in range(1, 6):
                surface = f"{surface_prefix}{tone}"
                full = f"{full_prefix}{tone}"
                with self.subTest(surface=surface, full=full):
                    self.assertEqual(self.encoder.normalize_ganyin_name(surface), full)
                    self.assertIn(full, self.source_keys)
                    self.assertNotIn(surface, self.source_keys)
                    self.assertEqual(
                        self.encoder.encode_ganyin(surface),
                        self.encoder.encode_ganyin(full),
                    )

    def test_slicer_recognizes_complete_rising_and_falling_contours(self):
        slicer = GanyinSlicer()
        rising = slicer.slice_ganyin(
            "single quality ganyin",
            {"a2": {"ime": "a2", "ipa": "a˧˦˥"}},
        )["a2"]
        falling = slicer.slice_ganyin(
            "single quality ganyin",
            {"a4": {"ime": "a4", "ipa": "a˥˦˩"}},
        )["a4"]

        assert rising == {"呼音": "a˧", "主音": "a˦", "末音": "a˥"}
        assert falling == {"呼音": "a˥", "主音": "a˦", "末音": "a˩"}

    def test_slicer_keeps_combining_diacritics_inside_quality_positions(self):
        slicer = GanyinSlicer()
        single = slicer.slice_ganyin(
            "single quality ganyin",
            {"a1": {"ime": "a1", "ipa": "ä˥˥˥"}},
        )["a1"]
        triple = slicer.slice_ganyin(
            "triple quality ganyin",
            {"ing1": {"ime": "ing1", "ipa": "iɘ̠̆ŋ˥˥˥"}},
        )["ing1"]

        assert single == {"呼音": "ä˥", "主音": "ä˥", "末音": "ä˥"}
        assert triple == {"呼音": "i˥", "主音": "ɘ̠̆˥", "末音": "ŋ˥"}

    def test_modern_ipa_symbols_keep_registered_quality_classes(self):
        mapper = YueyinMapper(SYLLABLE_DIR / "yinyuan" / "variables_of_attributes.json")
        for modern, registered in (
            ("ʊ", "ᴜ"),
            ("ä", "a"),
            ("ɛ̞", "æ"),
            ("e̞", "e"),
            ("ə̆", "ə"),
            ("ɘ̠̆", "𐞑"),
            ("m̩", "m"),
            ("n̩", "n"),
            ("ŋ̩", "ŋ"),
        ):
            with self.subTest(modern=modern, registered=registered):
                self.assertEqual(
                    mapper.normalize_symbol(modern, "˥"),
                    mapper.normalize_symbol(registered, "˥"),
                )

    def test_invalid_ganyin_inputs_raise_value_error(self):
        """无效输入应统一抛出 ValueError。"""
        invalid_cases: Final[list[object]] = [
            "",
            "xyz",
            "i6",
            "a0",
            "invalid",
            None,
            123,
        ]

        for invalid in invalid_cases:
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "无效的干音输入"):
                    self.encoder.encode_ganyin(cast(Any, invalid))

if __name__ == '__main__':
    unittest.main()
