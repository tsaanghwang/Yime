import unittest
import os
import sys
import json
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from final_classifier import FinalsClassifier

class TestFinalsClassifier(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test_data = {
            "i": "i", "u": "u", "n̍": "n", 
            "iᴀ": "ia", "uo": "uo", "ʏᴇ": "üe",
            "æɪ": "ai", "ɑᴜ": "ao", "iɑᴜ": "iao"
        }
        cls.output_file = "data_json_files/test_output.json"
        
    def test_count_symbols(self):
        """测试组合字符计数"""
        classifier = FinalsClassifier("", "")
        
        # 单质韵母
        self.assertEqual(classifier.count_symbols("i"), 1)
        self.assertEqual(classifier.count_symbols("n̍"), 1)  # 组合字符
        
        # 复合韵母
        self.assertEqual(classifier.count_symbols("iᴀ"), 2)
        self.assertEqual(classifier.count_symbols("æɪ"), 2)
        
    def test_is_back_long(self):
        """测试后长韵母判断"""
        classifier = FinalsClassifier("", "")
        
        # 后长韵母用例
        self.assertTrue(classifier.is_back_long("iᴀ"))  # i + ᴀ
        self.assertTrue(classifier.is_back_long("uo"))   # u + o
        
        # 前长韵母用例
        self.assertFalse(classifier.is_back_long("æɪ"))  # æ + ɪ
        self.assertFalse(classifier.is_back_long("ɑᴜ"))  # ɑ + ᴜ
        
    def test_full_classification(self):
        """测试完整分类流程"""
        # 准备临时测试文件
        test_input = "test_input.json"
        with open(test_input, 'w', encoding='utf-8') as f:
            json.dump(self.test_data, f)
            
        # 运行分类
        classifier = FinalsClassifier(test_input, self.output_file)
        classifier.run()
        
        # 验证结果
        with open(self.output_file, 'r', encoding='utf-8') as f:
            result = json.load(f)
            
        self.assertEqual(len(result["单质韵母"]), 3)  # i, u, n̍
        self.assertEqual(len(result["后长韵母"]), 2)  # iᴀ, uo
        self.assertEqual(len(result["前长韵母"]), 2)  # æɪ, ɑᴜ
        self.assertEqual(len(result["三质韵母"]), 1)  # iɑᴜ
        
        # 清理测试文件
        os.remove(test_input)
        os.remove(self.output_file)

if __name__ == '__main__':
    unittest.main()