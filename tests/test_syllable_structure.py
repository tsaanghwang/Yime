# yime/test_syllable_structure.py
import unittest
from yime.syllable_structure import SyllableStructure

class TestSyllableStructure(unittest.TestCase):
    """测试音节结构类"""

    def test_init_with_all_parameters(self):
        """测试使用所有参数初始化"""
        syllable = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        self.assertEqual(syllable.initial, "zh")
        self.assertEqual(syllable.ascender, "o")
        self.assertEqual(syllable.peak, "n")
        self.assertEqual(syllable.descender, "g")

    def test_init_with_partial_parameters(self):
        """测试使用部分参数初始化"""
        syllable = SyllableStructure(initial="zh", peak="a")
        self.assertEqual(syllable.initial, "zh")
        self.assertIsNone(syllable.ascender)
        self.assertEqual(syllable.peak, "a")
        self.assertIsNone(syllable.descender)

    def test_init_with_no_parameters(self):
        """测试无参数初始化"""
        syllable = SyllableStructure()
        self.assertIsNone(syllable.initial)
        self.assertIsNone(syllable.ascender)
        self.assertIsNone(syllable.peak)
        self.assertIsNone(syllable.descender)

    def test_ganyin_property_full(self):
        """测试干音属性（完整）"""
        syllable = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        self.assertEqual(syllable.ganyin, "ong")

    def test_ganyin_property_partial(self):
        """测试干音属性（部分）"""
        syllable = SyllableStructure(ascender="a", peak="i")
        self.assertEqual(syllable.ganyin, "ai")

    def test_ganyin_property_empty(self):
        """测试干音属性（空）"""
        syllable = SyllableStructure(initial="zh")
        self.assertEqual(syllable.ganyin, "")

    def test_rime_property(self):
        """测试韵音属性"""
        syllable = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        rime = syllable.rime
        self.assertEqual(rime['peak'], "n")
        self.assertEqual(rime['descender'], "g")

    def test_rime_property_empty(self):
        """测试韵音属性（空）"""
        syllable = SyllableStructure(initial="zh", ascender="a")
        rime = syllable.rime
        self.assertIsNone(rime['peak'])
        self.assertIsNone(rime['descender'])

    def test_classify_codes_full(self):
        """测试音元分类（完整）"""
        syllable = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, ["zh"])
        self.assertEqual(musical, ["o", "n", "g"])

    def test_classify_codes_partial(self):
        """测试音元分类（部分）"""
        syllable = SyllableStructure(initial="zh", peak="a")
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, ["zh"])
        self.assertEqual(musical, ["a"])

    def test_classify_codes_empty(self):
        """测试音元分类（空）"""
        syllable = SyllableStructure()
        noise, musical = syllable.classify_codes()
        self.assertEqual(noise, [])
        self.assertEqual(musical, [])

    def test_split_encoded_syllable_basic(self):
        """测试分割编码音节（基本）"""
        result = SyllableStructure.split_encoded_syllable("zhong")
        self.assertIsNotNone(result)
        self.assertIsInstance(result, SyllableStructure)

    def test_split_encoded_syllable_short(self):
        """测试分割编码音节（短）"""
        result = SyllableStructure.split_encoded_syllable("a")
        self.assertIsNotNone(result)
        self.assertEqual(result.initial, "a")

    def test_split_encoded_syllable_empty(self):
        """测试分割编码音节（空）"""
        with self.assertRaises(ValueError):
            SyllableStructure.split_encoded_syllable("")

    def test_split_encoded_syllable_various_lengths(self):
        """测试分割不同长度的编码音节"""
        test_cases = ["a", "ab", "abc", "abcd", "abcde"]
        for case in test_cases:
            result = SyllableStructure.split_encoded_syllable(case)
            self.assertIsNotNone(result)
            self.assertIsInstance(result, SyllableStructure)

    def test_syllable_reconstruction(self):
        """测试音节重构"""
        syllable = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        # 重构完整音节
        full_syllable = (syllable.initial or '') + syllable.ganyin
        self.assertEqual(full_syllable, "zhong")

    def test_syllable_equality(self):
        """测试音节相等性"""
        syllable1 = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        syllable2 = SyllableStructure(
            initial="zh",
            ascender="o",
            peak="n",
            descender="g"
        )
        # 验证属性相等
        self.assertEqual(syllable1.initial, syllable2.initial)
        self.assertEqual(syllable1.ascender, syllable2.ascender)
        self.assertEqual(syllable1.peak, syllable2.peak)
        self.assertEqual(syllable1.descender, syllable2.descender)

    def test_syllable_inequality(self):
        """测试音节不相等性"""
        syllable1 = SyllableStructure(initial="zh", peak="a")
        syllable2 = SyllableStructure(initial="ch", peak="a")
        self.assertNotEqual(syllable1.initial, syllable2.initial)

    def test_multiple_syllables(self):
        """测试多个音节"""
        syllables = [
            SyllableStructure(initial="zh", ascender="o", peak="n", descender="g"),
            SyllableStructure(initial="g", ascender="u", peak="o"),
            SyllableStructure(initial="r", ascender="e", peak="n"),
        ]

        # 验证每个音节
        self.assertEqual(syllables[0].ganyin, "ong")
        self.assertEqual(syllables[1].ganyin, "uo")
        self.assertEqual(syllables[2].ganyin, "en")

    def test_syllable_modification(self):
        """测试音节修改"""
        syllable = SyllableStructure(initial="zh", peak="a")
        self.assertEqual(syllable.ganyin, "a")

        # 修改属性
        syllable.ascender = "i"
        self.assertEqual(syllable.ganyin, "ia")

        syllable.descender = "ng"
        self.assertEqual(syllable.ganyin, "iang")

if __name__ == '__main__':
    unittest.main()
