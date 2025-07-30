#!/usr/bin/env python3
"""
最终验证：干音和韵母的定义与处理
"""

from ganyin import GanyinCategorizer
import json

def comprehensive_verification():
    """全面验证干音和韵母的定义与处理"""
    print("=== 最终验证：干音和韵母定义 ===")

    # 1. 确认定义
    print("1. 术语定义确认:")
    print("   - 干音 (ganyin) = final with tone (带声调的韵母)")
    print("   - 韵母 (final) = ganyin without tone (去掉声调的干音)")
    print("   - 预定义韵母集合包含的都是不带声调的韵母")
    print()

    # 2. 运行完整分析
    print("2. 执行完整分析...")
    analyzer = GanyinCategorizer.GanyinAnalyzer()
    success = analyzer.analyze_and_save()

    if not success:
        print("   分析失败!")
        return

    # 3. 验证韵母集合
    print("\n3. 验证预定义韵母集合（应该都是不带声调的）:")
    all_finals = GanyinCategorizer.get_all_finals()

    for category, finals_set in all_finals.items():
        print(f"   {category}: {len(finals_set)} 个韵母")
        for final in sorted(finals_set):
            # 检查是否有声调标记
            tone_chars = 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜếề'
            has_tone = any(char in final for char in tone_chars)
            if has_tone:
                print(f"     ⚠ {final} - 包含声调标记（可能有问题）")
            else:
                print(f"     ✓ {final} - 韵母（不带声调）")

    # 4. 验证干音数据
    print("\n4. 验证生成的干音数据:")
    with open(analyzer.ganyin_path, 'r', encoding='utf-8') as f:
        ganyin_data = json.load(f)

    ganyin_dict = ganyin_data.get('ganyin', {})
    print(f"   总共生成 {len(ganyin_dict)} 条干音数据")

    # 检查几个示例
    examples = [
        ('a1', 'ā'), ('ai2', 'ái'), ('ian3', 'iǎn'),
        ('ong4', 'òng'), ('iong1', 'iōng')
    ]

    print("   示例验证:")
    for key, expected in examples:
        if key in ganyin_dict:
            actual = ganyin_dict[key]
            print(f"     {key} -> {actual} (预期: {expected}) {'✓' if actual == expected else '✗'}")

            # 提取韵母
            final = GanyinCategorizer._normalize_final(key)
            category = GanyinCategorizer.categorize(actual)
            print(f"       提取的韵母: {final}, 分类: {category}")
        else:
            print(f"     {key} -> 未找到")

    # 5. 统计分析
    print("\n5. 最终统计:")
    total_finals = sum(len(finals) for finals in all_finals.values())
    print(f"   - 韵母总数: {total_finals}")
    print(f"   - 干音总数: {len(ganyin_dict)}")
    print(f"   - 干音是韵母的带声调形式，一个韵母对应多个干音（不同声调）")

    # 验证比例关系
    expected_ganyin_count = total_finals * 5  # 每个韵母5个声调
    special_count = len(GanyinCategorizer.SPECIAL_SYLLABLES)
    actual_ratio = len(ganyin_dict) / total_finals if total_finals > 0 else 0

    print(f"   - 预期比例: ~5:1 (每个韵母5个声调)")
    print(f"   - 实际比例: {actual_ratio:.2f}:1")
    print(f"   - 特殊音节数: {special_count}")

if __name__ == "__main__":
    comprehensive_verification()
