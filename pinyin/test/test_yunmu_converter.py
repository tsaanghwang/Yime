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

    def test_plugin_loading(self):
        """测试插件加载"""
        # 创建模拟插件
        mock_plugin = MagicMock()
        mock_plugin.get_rules.return_value = []
        
        # 使用自定义插件创建转换器
        converter = YunmuConverter(plugins=[mock_plugin])
        
        # 验证插件加载
        self.assertEqual(len(converter.plugins), 1)
        mock_plugin.get_rules.assert_called_once()

    def test_invalid_input(self):
        """测试无效输入处理"""
        with self.assertRaises(ValueError):
            self.converter.convert({"invalid": ""})

if __name__ == '__main__':
    unittest.main()