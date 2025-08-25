#!/usr/bin/env python3
"""
验证新添加韵母的分类是否合理
"""

from syllable_categorizer import SyllableCategorizer


def analyze_new_finals():
    """分析新添加韵母的分类合理性"""
    print("=== 验证新添加韵母分类的合理性 ===")

    # 从运行结果中提取的新添加韵母
    new_finals = ['ian', 'iong', 'iu', 'ong', 'ua',
                  'uai', 'ue', 'ui', 'un', 'v', 'van', 've']

    print("新添加的韵母及其分类:")
    for final in new_finals:
        category = SyllableCategorizer.categorize(final)
        print(f"  '{final}' -> {category}")

        # 分析分类合理性
        if final == 'ian':
            expected = "后长干音"  # i + an，以i开头的复合韵母
        elif final == 'iong':
            expected = "三质干音"  # i + ong，长复合韵母
        elif final == 'iu':
            expected = "单质干音"  # 短韵母
        elif final == 'ong':
            expected = "前长干音"  # 以o开头，不以i/u/ü开头
        elif final == 'ua':
            expected = "单质干音"  # 短韵母
        elif final == 'uai':
            expected = "后长干音"  # u + ai，以u开头的复合韵母
        elif final == 'ue':
            expected = "单质干音"  # 短韵母
        elif final == 'ui':
            expected = "单质干音"  # 短韵母
        elif final == 'un':
            expected = "单质干音"  # 短韵母
        elif final == 'v':
            expected = "单质干音"  # 单个字符
        elif final == 'van':
            expected = "前长干音"  # v + an
        elif final == 've':
            expected = "单质干音"  # 短韵母
        else:
            expected = "不确定"

        if category == expected:
            print(f"    ✓ 分类正确")
        else:
            print(f"    ⚠ 预期: {expected}, 实际: {category}")

    print("\n=== 韵母分类统计 ===")
    all_finals = SyllableCategorizer.get_all_finals()
    total = sum(len(finals) for finals in all_finals.values())

    for category, finals in all_finals.items():
        count = len(finals)
        percentage = (count / total) * 100
        print(f"{category}: {count} 个韵母 ({percentage:.1f}%)")

    print(f"\n总韵母数量: {total}")


if __name__ == "__main__":
    analyze_new_finals()
