import unittest
import json
from tools.ganyin_analyzer import GanyinAnalyzer

class TestGanyinAnalyzer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        """加载测试数据"""
        with open("internal_data/classified_finals.json", "r", encoding="utf-8") as f:
            cls.finals_data = json.load(f)
        
        cls.analyzer = GanyinAnalyzer()
    
    def test_first_tone_analysis(self):
        """测试第一声(阴平)分析"""
        test_final = {"音标": "uan", "拼音": "uan"}
        expected = ["u˥", "a˥", "n˥"]
        result = self.analyzer.analyze_final(test_final, "first_tone")
        self.assertEqual(result, expected)
    
    def test_second_tone_analysis(self):
        """测试第二声(阳平)分析"""
        test_final = "ian"
        expected = ["i˩", "a˧", "n˥"]
        result = self.analyzer.analyze_final(test_final, "second_tone")
        self.assertEqual(result, expected)
    
    def test_third_tone_analysis(self):
        """测试第三声(上声)分析"""
        test_final = "uai"
        expected = ["u˩", "a˩", "i˩"]
        result = self.analyzer.analyze_final(test_final, "third_tone")
        self.assertEqual(result, expected)
    
    def test_fourth_tone_analysis(self):
        """测试第四声(去声)分析"""
        test_final = "iao"
        expected = ["i˥", "a˧", "o˩"]
        result = self.analyzer.analyze_final(test_final, "fourth_tone")
        self.assertEqual(result, expected)
    
    def test_invalid_final_length(self):
        """测试非三质韵母的异常处理"""
        with self.assertRaises(ValueError):
            self.analyzer.analyze_final(
                {"音标": "ua", "拼音": "ua"}, 
                "first_tone"
            )
    
    def test_invalid_tone_type(self):
        """测试无效声调类型的异常处理"""
        with self.assertRaises(ValueError):
            self.analyzer.analyze_final("uan", "fifth_tone")
    
    def test_analyze_all_finals(self):
        """测试批量分析功能"""
        results = self.analyzer.analyze_all_finals(self.finals_data)
        self.assertIn("first_tone", results)
        self.assertIn("second_tone", results)
        
        # 检查每个声调类型下都有韵母分类
        for tone in self.analyzer.tone_patterns:
            with self.subTest(tone=tone):
                self.assertIn(tone, results)
                for final_type in self.finals_data:
                    self.assertIn(final_type, results[tone])

if __name__ == "__main__":
    unittest.main()