# yime/test_syllable_decoder.py
import unittest
import json
import tempfile
import os
from pathlib import Path
from yime.syllable_decoder import (
    SyllableDecoder,
    is_pua_string,
    is_valid_encoded_string,
    _normalize_split
)

class TestSyllableDecoder(unittest.TestCase):
    """测试音节解码器"""

    def setUp(self):
        """设置测试环境"""
        # 创建临时编码文件
        self.temp_file = tempfile.NamedTemporaryFile(
            mode='w', delete=False, suffix='.json', encoding='utf-8'
        )

        # 写入测试数据
        test_code_map = {
            "zhong": "中",
            "guo": "国",
            "ren": "人",
            "min": "民",
            "test": "测试"
        }
        json.dump(test_code_map, self.temp_file, ensure_ascii=False)
        self.temp_file.close()

        # 创建解码器实例
        self.decoder = SyllableDecoder(code_file=self.temp_file.name)

    def tearDown(self):
        """清理测试文件"""
        if os.path.exists(self.temp_file.name):
            os.unlink(self.temp_file.name)

    def test_init_with_custom_file(self):
        """测试使用自定义文件初始化"""
        decoder = SyllableDecoder(code_file=self.temp_file.name)
        self.assertIsNotNone(decoder.code_map)
        self.assertGreater(len(decoder.code_map), 0)

    def test_init_with_nonexistent_file(self):
        """测试使用不存在的文件初始化"""
        decoder = SyllableDecoder(code_file="nonexistent.json")
        self.assertEqual(decoder.code_map, {})

    def test_load_code_map(self):
        """测试加载编码映射"""
        self.assertIn("zhong", self.decoder.code_map)
        self.assertEqual(self.decoder.code_map["zhong"], "中")

    def test_get_code_existing(self):
        """测试获取已存在的编码"""
        code = self.decoder._get_code("zhong")
        self.assertEqual(code, "中")

    def test_get_code_nonexistent(self):
        """测试获取不存在的编码"""
        code = self.decoder._get_code("nonexistent")
        self.assertIsNone(code)

    def test_get_code_by_value(self):
        """测试通过值反查编码"""
        code = self.decoder._get_code("中")
        self.assertEqual(code, "中")

    def test_split_encoded_syllable_basic(self):
        """测试基本音节分割"""
        # 测试简单编码
        result = self.decoder.split_encoded_syllable("zhong")
        # 结果可能是 None 或 SyllableStructure 实例
        # 这里只验证不会抛出异常
        self.assertIsNotNone(result)

    def test_split_encoded_syllable_empty(self):
        """测试空字符串分割"""
        # 空字符串应该抛出 ValueError
        with self.assertRaises(ValueError):
            self.decoder.split_encoded_syllable("")


class TestUtilityFunctions(unittest.TestCase):
    """测试工具函数"""

    def test_is_pua_string_empty(self):
        """测试空字符串 PUA 判断"""
        self.assertFalse(is_pua_string(""))

    def test_is_pua_string_normal(self):
        """测试普通字符串 PUA 判断"""
        self.assertFalse(is_pua_string("hello"))
        self.assertFalse(is_pua_string("中文"))

    def test_is_valid_encoded_string_empty(self):
        """测试空字符串有效性判断"""
        self.assertFalse(is_valid_encoded_string(""))

    def test_is_valid_encoded_string_normal(self):
        """测试普通字符串有效性判断"""
        self.assertTrue(is_valid_encoded_string("zhong"))
        self.assertTrue(is_valid_encoded_string("guo"))

    def test_normalize_split_none(self):
        """测试 None 输入归一化"""
        result = _normalize_split(None)
        self.assertIsNone(result)

    def test_normalize_split_empty(self):
        """测试空列表归一化"""
        result = _normalize_split([])
        self.assertIsNone(result)

    def test_normalize_split_four_elements(self):
        """测试四元素列表归一化"""
        input_data = ("zh", None, ("o", "ng"), ("", ""))
        result = _normalize_split(input_data)
        self.assertEqual(result, input_data)

    def test_normalize_split_three_elements(self):
        """测试三元素列表归一化"""
        input_data = ("zh", None, ("o", "ng"))
        result = _normalize_split(input_data)
        self.assertIsNotNone(result)
        self.assertEqual(len(result), 4)

    def test_normalize_split_invalid(self):
        """测试无效输入归一化"""
        result = _normalize_split("invalid")
        self.assertIsNone(result)


class TestSyllableDecoderIntegration(unittest.TestCase):
    """集成测试"""

    def setUp(self):
        """设置集成测试环境"""
        # 使用默认编码文件（如果存在）
        try:
            self.decoder = SyllableDecoder()
        except Exception:
            self.decoder = None

    def test_decoder_initialization(self):
        """测试解码器初始化"""
        if self.decoder is None:
            self.skipTest("解码器初始化失败")

        self.assertIsNotNone(self.decoder.code_file)
        self.assertIsInstance(self.decoder.code_map, dict)

    def test_real_world_decoding(self):
        """测试真实场景解码"""
        if self.decoder is None:
            self.skipTest("解码器初始化失败")

        if len(self.decoder.code_map) == 0:
            self.skipTest("编码映射为空")

        # 尝试解码一些常见音节
        test_cases = ["zhong", "guo", "ren", "min"]
        for case in test_cases:
            try:
                result = self.decoder.split_encoded_syllable(case)
                # 只验证不会抛出异常
                self.assertIsNotNone(result)
            except Exception as e:
                self.fail(f"解码 '{case}' 时发生异常: {e}")

if __name__ == '__main__':
    unittest.main()
