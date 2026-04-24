import json
import unittest
from pathlib import Path
from typing import Any, Final, cast

try:
    from .ganyin_encoder import GanyinEncoder
except ImportError:
    from ganyin_encoder import GanyinEncoder

class TestGanyinEncoder(unittest.TestCase):
    """干音编码器完备测试"""

    @classmethod
    def setUpClass(cls):
        mapping_path = Path(__file__).parent / "yinyuan" / "ganyin_to_fixed_length_yinyuan_sequence.json"
        with mapping_path.open('r', encoding='utf-8') as file:
            cls.encoding_map = json.load(file)

        cls.encoder = GanyinEncoder()
        cls.expected_keys = set(cls.encoding_map)
        cls.source_keys = set(cls.encoder.ganyin_part_map)

    def test_encoding_snapshot_matches_source_keys(self):
        """快照文件应完整覆盖当前编码器可处理的全部干音键。"""
        self.assertEqual(self.expected_keys, self.source_keys)

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

    def test_h_nasal_aliases_normalize_to_base_ganyin(self):
        """hm/hn/hng 应通过归并规则复用 m/n/ng 的编码。"""
        alias_pairs = (("hm", "m"), ("hn", "n"), ("hng", "ng"))

        for alias_prefix, base_prefix in alias_pairs:
            for tone in range(1, 6):
                alias = f"{alias_prefix}{tone}"
                base = f"{base_prefix}{tone}"
                with self.subTest(alias=alias, base=base):
                    self.assertEqual(
                        self.encoder.encode_ganyin(alias),
                        self.encoder.encode_ganyin(base),
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
