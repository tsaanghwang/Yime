
import unittest
import json
from pathlib import Path
from shouyin_encoder import ShouyinEncoder

class TestShouyinEncoder(unittest.TestCase):
    """测试 ShouyinEncoder 类的 encode_shouyin 方法"""

    @classmethod
    def setUpClass(cls):
        """测试类初始化，创建编码器实例"""
        data_path = Path(__file__).parent / "yinyuan" / "zaoyin_yinyuan_enhanced.json"
        cls.encoder = ShouyinEncoder(data_path)
        runtime_path = Path(__file__).parent / "yinyuan" / "shouyin_codepoint.json"
        with runtime_path.open('r', encoding='utf-8') as f:
            cls.runtime_map = json.load(f)["首音"]

    def test_encode_valid_shouyin(self):
        """测试有效首音编码"""
        for shouyin, expected in self.runtime_map.items():
            with self.subTest(shouyin=shouyin):
                result = self.encoder.encode_shouyin(shouyin)
                self.assertEqual(result, expected)
                print(f"测试通过: {shouyin} -> {result}")

    def test_encode_invalid_shouyin(self):
        """测试无效首音编码"""
        invalid_shouyin = ["a", "e", "o", "v", "@", "#", "1"]
        for shouyin in invalid_shouyin:
            with self.subTest(shouyin=shouyin):
                result = self.encoder.encode_shouyin(shouyin)
                self.assertEqual(result, "", f"无效首音 '{shouyin}' 应返回空字符串")

    def test_encode_empty_string(self):
        """测试空字符串输入"""
        result = self.encoder.encode_shouyin("")
        self.assertEqual(result, "", "空字符串输入应返回空字符串")

    def test_encode_complex_shouyin(self):
        """测试复合首音编码"""
        # 测试复合首音(如zh, ch, sh)是否保持完整
        test_cases = [(shouyin, self.runtime_map[shouyin]) for shouyin in ("zh", "ch", "sh")]
        for shouyin, expected in test_cases:
            with self.subTest(shouyin=shouyin):
                result = self.encoder.encode_shouyin(shouyin)
                self.assertEqual(result, expected)
                print(f"复合首音测试通过: {shouyin} -> {result}")

def main():
    """运行测试并打印结果"""
    print("开始测试 ShouyinEncoder.encode_shouyin() 功能...")
    unittest.main(argv=[''], exit=False)

if __name__ == "__main__":
    main()
