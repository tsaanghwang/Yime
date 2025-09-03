import unittest
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from syllable.analysis.slice.ganyin_encoder import GanyinEncoder

class TestGanyinEncoder(unittest.TestCase):
    """干音编码器完备测试"""

    @classmethod
    def setUpClass(cls):
        # 加载编码映射文件
        mapping_path = Path(__file__).parent / "yinyuan" / "ganyin_to_fixed_length_yinyuan_sequence.json"
        with open(mapping_path, 'r', encoding='utf-8') as f:
            cls.encoding_map = json.load(f)

        # 初始化编码器
        cls.encoder = GanyinEncoder()

    def test_all_ganyin_encodings(self):
        """测试所有干音编码映射"""
        for ganyin, expected in self.encoding_map.items():
            with self.subTest(ganyin=ganyin):
                result = self.encoder.encode_ganyin(ganyin)
                self.assertEqual(
                    result, expected,
                    f"干音 '{ganyin}' 编码错误: 预期 '{expected}' (U+{ord(expected[0]):04X}...), 实际得到 '{result}'"
                )

    def test_invalid_ganyin(self):
        """测试无效干音输入"""
        invalid_cases = [
            "",          # 空输入
            "xyz",       # 不存在干音
            "i6",        # 超出音调范围
            "a0",        # 0调不存在
            "invalid"    # 完全无效
        ]

        for invalid in invalid_cases:
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    self.encoder.encode_ganyin(invalid)

if __name__ == '__main__':
    unittest.main()
