import unittest
import json
from yinjie_encoder import YinjieEncoder

class TestYinjieEncoderLength(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 加载所有拼音音节
        with open('pinyin/hanzi_pinyin/pinyin_normalized.json', 'r', encoding='utf-8') as f:
            cls.all_pinyin = list(json.load(f).keys())
        cls.encoder = YinjieEncoder()

    def test_all_pinyin_length(self):
        """测试所有拼音音节的编码长度不超过4个码位"""
        for pinyin in self.all_pinyin:
            with self.subTest(pinyin=pinyin):
                encoded = self.encoder.encode_single_yinjie(pinyin)
                self.assertLessEqual(
                    len(encoded),
                    4,
                    f"拼音 '{pinyin}' 的编码 '{encoded}' 长度超过4个码位"
                )

if __name__ == '__main__':
    unittest.main()