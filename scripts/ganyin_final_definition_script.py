#!/usr/bin/env python3
"""
验证干音和韵母的定义和处理逻辑
"""
import  sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from syllable.analysis.slice.ganyin_categorizer import GanyinCategorizer


def test_ganyin_final_logic():
    """测试干音和韵母的处理逻辑"""
    print("=== 验证干音和韵母的定义 ===")

    # 测试用例：拼音 -> (声母, 干音)
    test_cases = [
        ("zhāng", "zh", "āng"),  # 干音 = āng, 韵母 = ang
        ("lǐ", "l", "ǐ"),        # 干音 = ǐ, 韵母 = i
        ("piāo", "p", "iāo"),    # 干音 = iāo, 韵母 = iao
        ("chuáng", "ch", "uáng"),  # 干音 = uáng, 韵母 = uang
    ]

    print("测试拼音切分:")
    for pinyin, expected_initial, expected_ganyin in test_cases:
        initial, ganyin = GanyinCategorizer.split_syllable(pinyin)
        final = GanyinCategorizer._remove_tone_from_ganyin(ganyin)
        category = GanyinCategorizer.categorize(ganyin)

        print(f"  拼音: {pinyin}")
        print(f"    声母: {initial} (预期: {expected_initial})")
        print(f"    干音: {ganyin} (预期: {expected_ganyin})")
        print(f"    韵母: {final}")
        print(f"    分类: {category}")
        print()

    print("=== 验证预定义韵母集合 ===")
    all_finals = GanyinCategorizer.get_all_finals()

    for category, finals in all_finals.items():
        print(f"{category}:")
        # 检查是否都是不带声调的韵母
        for final in sorted(finals):
            has_tone = any(
                char in final for char in 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ')
            if has_tone:
                print(f"  ⚠ {final} - 包含声调标记")
            else:
                print(f"  ✓ {final} - 不带声调")
        print()


if __name__ == "__main__":
    test_ganyin_final_logic()
