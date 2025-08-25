
import unittest
from pathlib import Path
from shouyin_encoder import ShouyinEncoder

class TestShouyinEncoder(unittest.TestCase):
    """测试 ShouyinEncoder 类的 encode_shouyin 方法"""

    @classmethod
    def setUpClass(cls):
        """测试类初始化，创建编码器实例"""
        # 使用默认的 zaoyin_yinyuan.json 文件路径
        data_path = Path(__file__).parent / "yinyuan" / "zaoyin_yinyuan.json"
        cls.encoder = ShouyinEncoder(data_path)

    def test_encode_valid_shouyin(self):
        """测试有效首音编码"""
        # 从 shouyin_codepoint.json 中获取已知首音映射
        test_cases = [
            ("b", "􀀀"),
            ("p", "􀀁"),
            ("f", "􀀂"),
            ("m", "􀀃"),
            ("d", "􀀄"),
            ("t", "􀀅"),
            ("l", "􀀆"),
            ("n", "􀀇"),
            ("g", "􀀈"),
            ("k", "􀀉"),
            ("h", "􀀊"),
            ("z", "􀀋"),
            ("c", "􀀌"),
            ("s", "􀀍"),
            ("zh", "􀀎"),
            ("ch", "􀀏"),
            ("sh", "􀀐"),
            ("r", "􀀑"),
            ("j", "􀀒"),
            ("q", "􀀓"),
            ("x", "􀀔"),
            ("'", "􀀕"),
            ("w", "􀀖"),
            ("y", "􀀗")
        ]

        for shouyin, expected in test_cases:
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
        test_cases = [
            ("zh", "􀀎"),
            ("ch", "􀀏"),
            ("sh", "􀀐")
        ]
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