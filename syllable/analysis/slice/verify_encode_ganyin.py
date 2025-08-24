"""
在syllable/analysis/slice/verify_encode_ganyin.py中，创建一个模块，
验证从外部调用 syllable/analysis/slice/ganyin_encoder.py内的函数 encode_shouyin的功能是否有效
"""

import unittest
import os
import sys
# 添加syllable的父目录到 Python 路径
# sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))
from ganyin_encoder import GanyinEncoder
# from ganyin_encoder import GanyinEncoder

class TestGanyinEncoder(unittest.TestCase):
    """测试 ganyin_encoder.py 中的 encode_ganyin 功能"""

    def setUp(self):
        self.encoder = GanyinEncoder()
        print("\n" + "="*50)
        print("干音编码验证（目视判断模式）")
        print("="*50)

    def test_encode_valid_ganyin(self):
        """测试有效干音编码（输出结果供目视判断）"""
        test_cases = [
            "a1", "i2", "u3", "ang4"  # 示例干音，可根据需要调整
        ]

        for ganyin in test_cases:
            result = self.encoder.encode_ganyin(ganyin)
            print(f"\n干音: '{ganyin}'")
            print(f"编码结果: {result}")
            print(f"Unicode转义序列: {','.join(f'U+{ord(c):04X}' for c in result)}")
            print(f"实际显示: {result}")

    def test_encode_invalid_ganyin(self):
        """测试无效干音编码（输出结果供目视判断）"""
        invalid_cases = [
            "", "invalid", "x9", None
        ]

        for ganyin in invalid_cases:
            result = self.encoder.encode_ganyin(ganyin)
            print(f"\n无效干音: '{ganyin}'")
            print(f"处理结果: {result}")

    def test_encode_edge_cases(self):
        """测试边界情况（输出结果供目视判断）"""
        edge_cases = [
            ("a", "缺少声调"),
            ("1", "只有声调"),
            ("a123", "声调格式错误"),
            (" a1", "前导空格"),
            ("a1 ", "尾部空格")
        ]

        for ganyin, case_type in edge_cases:
            result = self.encoder.encode_ganyin(ganyin)
            print(f"\n边界情况 - {case_type}: '{ganyin}'")
            print(f"处理结果: {result}")

if __name__ == "__main__":
    unittest.main()
