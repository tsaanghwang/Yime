import unittest

from yime.utils.pinyin_zhuyin import PinyinZhuyinConverter


class TestPinyinZhuyinConverter(unittest.TestCase):
    def test_special_syllables(self):
        cases = {
            "zhi1": "ㄓ̄",
            "chi2": "ㄔ́",
            "shi4": "ㄕ̀",
            "ri4": "ㄖ̀",
            "zi3": "ㄗ̌",
            "ci2": "ㄘ́",
            "si1": "ㄙ̄",
        }
        for pinyin, expected in cases.items():
            with self.subTest(pinyin=pinyin):
                self.assertEqual(PinyinZhuyinConverter.convert_pinyin_to_zhuyin(pinyin), expected)

    def test_zero_initial_syllables(self):
        cases = {
            "yi1": "ㄧ̄",
            "ying1": "ㄧㄥ̄",
            "wu3": "ㄨ̌",
            "yu3": "ㄩ̌",
            "yue4": "ㄩㄝ̀",
            "yuan2": "ㄩㄢ́",
        }
        for pinyin, expected in cases.items():
            with self.subTest(pinyin=pinyin):
                self.assertEqual(PinyinZhuyinConverter.convert_pinyin_to_zhuyin(pinyin), expected)

    def test_jqx_umlaut_normalization(self):
        cases = {
            "ju4": "ㄐㄩ̀",
            "qu2": "ㄑㄩ́",
            "xun1": "ㄒㄩㄣ̄",
            "lv4": "ㄌㄩ̀",
            "nv3": "ㄋㄩ̌",
        }
        for pinyin, expected in cases.items():
            with self.subTest(pinyin=pinyin):
                self.assertEqual(PinyinZhuyinConverter.convert_pinyin_to_zhuyin(pinyin), expected)

    def test_process_pinyin_dict(self):
        converted, mismatch_count = PinyinZhuyinConverter.process_pinyin_dict({
            "zhong1": "ignored",
            "yi1": "ignored",
        })
        self.assertEqual(converted["zhong1"], "ㄓㄨㄥ̄")
        self.assertEqual(converted["yi1"], "ㄧ̄")
        self.assertEqual(mismatch_count, 2)


if __name__ == "__main__":
    unittest.main()
