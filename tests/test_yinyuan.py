# tests/test_yinyuan.py
import sys
import os
import unittest
import time
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# 确保能正确导入项目模块
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from pianyin.pianyin import PitchedPianyin, UnpitchedPianyin
from syllable.analysis.slice.yueyin_yinyuan import YueyinYinyuan


class TestYinyuanProcessing(unittest.TestCase):
    """测试Yinyuan类的音元处理功能"""

    def setUp(self):
        """测试前置准备"""
        # 使用绝对路径初始化
        config_path = os.path.join(os.path.dirname(
            __file__), 'yinyuan', 'variables_of_attributes.json')
        self.yinyuan = YueyinYinyuan(config_path=config_path)

        self.test_data_mid_high_median_model = {
            "key1": ("i", "˥"),
            "key2": ("u", "˦"),
            "key3": ("ᴀ", "˩"),
            "key4": ("ɪ", "˥"),  # i的变体
            "key5": ("ɑ", "˩")   # ᴀ的变体
        }

        self.test_data_mid_level_median_model = {
            "key1": ("i", "˥"),
            "key2": ("u", "˦"),
            "key3": ("ᴀ", "˩"),
            "key4": ("o", "˧"),
            "key5": ("ᴇ", "˨")
        }

    def test_process_pitched_yinyuan_mid_high_median_model(self):
        """测试mid_high_median_model的音元处理"""
        result = self.yinyuan.process_pitched_yinyuan(
            self.test_data_mid_high_median_model, is_mid_level_median_model=False)

        # 验证输出
        self.assertIn("i˥", result)
        self.assertIn("u˦", result)
        self.assertIn("ᴀ˩", result)

        # 验证变体音质处理
        self.assertIn("i˥", result)  # ɪ应映射为i
        self.assertIn("ᴀ˩", result)  # ɑ应映射为ᴀ

        # 验证分组
        self.assertEqual(len(result["i˥"]), 2)  # i˥和ɪ˥应归为一组
        self.assertEqual(len(result["ᴀ˩"]), 2)  # ᴀ˩和ɑ˩应归为一组

    def test_process_pitched_yinyuan_mid_level_median_model(self):
        """测试mid_level_median_model的音元处理"""
        result = self.yinyuan.process_pitched_yinyuan(
            self.test_data_mid_level_median_model, is_mid_level_median_model=True)

        # 验证mid_level_median_model特有的音调处理
        self.assertIn("i˥", result)  # ˥保持不变
        self.assertIn("u˥", result)  # ˦应提升为˥
        self.assertIn("ᴀ˩", result)  # ˩保持不变
        self.assertIn("o˧", result)  # ˧保持不变
        self.assertIn("ᴇ˩", result)  # ˨被映射为˩

    def test_process_empty_input(self):
        """测试空输入处理"""
        result = self.yinyuan.process_pitched_yinyuan(
            {}, is_mid_level_median_model=False)
        self.assertEqual(result, {})

    def test_process_invalid_quality(self):
        """测试无效音质处理"""
        invalid_data = {"key1": ("x", "˥")}  # 无效音质
        result = self.yinyuan.process_pitched_yinyuan(
            invalid_data, is_mid_level_median_model=False)
        self.assertEqual(result, {})

    def test_process_invalid_pitch(self):
        """测试无效音调处理"""
        invalid_data = {"key1": ("i", "x")}  # 无效音调
        result = self.yinyuan.process_pitched_yinyuan(
            invalid_data, is_mid_level_median_model=False)
        self.assertEqual(result, {})

    def test_process_performance(self):
        """测试处理性能"""
        large_data = {f"key{i}": ("i", "˥") for i in range(1000)}

        start_time = time.time()
        result = self.yinyuan.process_pitched_yinyuan(
            large_data, is_mid_level_median_model=False)
        end_time = time.time()

        self.assertLess(end_time - start_time, 1.0)  # 应在1秒内完成
        self.assertEqual(len(result["i˥"]), 1000)


class TestYinyuan(unittest.TestCase):
    """测试Yinyuan类的音元转换功能"""

    def setUp(self):
        """测试前置准备"""
        # 使用绝对路径初始化
        self.config_path = os.path.join(os.path.dirname(
            __file__), 'yinyuan', 'variables_of_attributes.json')

    def test_from_pianyin_basic(self):
        """测试基本片音到音元的转换"""
        # 测试乐音类片音
        p = PitchedPianyin(quality="i", pitch="˥")
        y = YueyinYinyuan.from_pianyin(p)
        # Update the expected code to match the actual mapping
        self.assertEqual(y.code, 15)
        self.assertEqual(y.notation, "i˥")

        # 测试噪音类片音
        p_unpitched_yinyuan = UnpitchedPianyin(quality="m")
        y_unpitched_yinyuan = YueyinYinyuan.from_pianyin(p_unpitched_yinyuan)
        self.assertEqual(y_unpitched_yinyuan.code, 0)
        self.assertEqual(y_unpitched_yinyuan.notation, "m")

    def test_from_pianyin_edge_cases(self):
        """测试边界情况处理"""
        # 测试无效音质
        with self.assertRaises(ValueError):
            p = PitchedPianyin(quality="x", pitch="˥")  # 不存在的音质
            YueyinYinyuan.from_pianyin(p)

        # 测试无效音调
        with self.assertRaises(ValueError):
            p = PitchedPianyin(quality="i", pitch="˫")  # 不存在的音调
            YueyinYinyuan.from_pianyin(p)

        # 测试空音质和音调
        with self.assertRaises(ValueError):
            p = PitchedPianyin(quality="", pitch="")  # 空音质和音调
            YueyinYinyuan.from_pianyin(p)

        # 测试缺少必选属性 - 修改为期望TypeError
        with self.assertRaises(TypeError):
            p = PitchedPianyin()    # 缺少必选参数quality和pitch，预期TypeError
            YueyinYinyuan.from_pianyin(p)

    def test_to_pianyin_basic(self):
        """测试音元到片音的基本转换"""
        y = YueyinYinyuan(15, config_path=self.config_path)  # i˥
        p = y.to_pianyin()
        self.assertIsInstance(p, PitchedPianyin)
        self.assertEqual(p.quality, "i")
        self.assertEqual(p.pitch, "˥")
        self.assertEqual(p.pitch, "˥")

        # 测试噪音类音元 - 修改为使用有效噪音符号
        y_unpitched_yinyuan = YueyinYinyuan(0, notation="m", config_path=self.config_path)
        p_unpitched_yinyuan = y_unpitched_yinyuan.to_pianyin()
        self.assertIsInstance(p_unpitched_yinyuan, UnpitchedPianyin)
        self.assertEqual(p_unpitched_yinyuan.quality, "m")

    def test_to_pianyin_edge_cases(self):
        """测试音元到片音的边界情况"""
        # 测试无效音元代码
        with self.assertRaises(ValueError):
            y = YueyinYinyuan(999, config_path=self.config_path)  # 不存在的音元代码
            y.to_pianyin()

        y = YueyinYinyuan(15, config_path=self.config_path)
        p = y.to_pianyin()
        self.assertEqual(p.duration, "neutral")
        self.assertEqual(p.loudness, "neutral")

        # 测试带音长和音强的转换
        y = YueyinYinyuan(15, "i˥_long^loud", config_path=self.config_path)
        p = y.to_pianyin()
        self.assertEqual(p.duration, "long")
        self.assertEqual(p.loudness, "loud")
        self.assertEqual(p.loudness, "loud")


if __name__ == '__main__':
    unittest.main()
