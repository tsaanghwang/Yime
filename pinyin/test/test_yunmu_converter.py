import unittest
from unittest.mock import MagicMock
from pinyin.yunmu_to_keys import YunmuConverter
from pinyin.constants import YunmuConstants

class TestYunmuConverter(unittest.TestCase):
    def setUp(self):
        """初始化测试环境"""
        # 使用YunmuConstants获取完整韵母列表
        self.constants = YunmuConstants()
        self.full_yunmu_dict = {yunmu: "" for yunmu in self.constants.REQUIRED_FINALS}
        
        # 创建转换器实例
        self.converter = YunmuConverter()

    def test_basic_conversion(self):
        """测试基本转换功能"""
        # 使用完整韵母字典
        result = self.converter.convert(self.full_yunmu_dict)
        
        # 验证转换结果不为空
        self.assertTrue(all(len(v) > 0 for v in result.values()))
        
        # 验证几个关键转换
        self.assertEqual(result["-i"], "ir")
        self.assertEqual(result["ao"], "au")
        self.assertEqual(result["ü"], "v")

    def test_statistics(self):
        """测试统计功能"""
        # 执行转换
        result = self.converter.convert(self.full_yunmu_dict)
        
        # 获取统计信息
        stats = self.converter.get_stats()
        
        # 验证基本统计
        self.assertEqual(stats["total_conversions"], len(self.full_yunmu_dict))
        self.assertEqual(stats["successful_conversions"], len(self.full_yunmu_dict))
        self.assertEqual(stats["success_rate"], 100.0)

    def test_rule_application(self):
        """测试规则应用"""
        # 先执行完整转换
        result = self.converter.convert(self.full_yunmu_dict)

        # 验证特定韵母的转换规则
        test_cases = {
            "-i": "ir",      # 舌尖元音转换
            "ao": "au",      # ao->au转换
            "iao": "iau",    # iao->iau转换
            "ü": "v",        # ü->v转换
        }

        for yunmu, expected in test_cases.items():
            self.assertEqual(result[yunmu], expected,
                           f"转换 {yunmu} 应该得到 {expected}，但得到 {result[yunmu]}")

    def test_invalid_input(self):
        """测试无效输入处理"""
        with self.assertRaises(ValueError):
            self.converter.convert({"invalid": ""})

if __name__ == '__main__':
    unittest.main()