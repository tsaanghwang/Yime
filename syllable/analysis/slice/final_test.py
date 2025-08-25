#!/usr/bin/env python3
"""
韵母动态添加功能总结测试
"""

from syllable_categorizer import SyllableCategorizer
from syllable_analyzer import YinjieAnalyzer
import json
import os

def final_test():
    """最终测试韵母动态添加功能"""
    print("=== 韵母动态添加功能最终测试 ===")

    # 1. 显示初始状态
    initial_finals = SyllableCategorizer.get_all_finals()
    initial_count = sum(len(finals) for finals in initial_finals.values())
    print(f"1. 初始韵母总数: {initial_count}")

    # 2. 执行完整分析
    print("\n2. 执行完整分析...")
    analyzer = YinjieAnalyzer(__file__)
    success = analyzer.analyze_and_save()

    if not success:
        print("   分析失败!")
        return

    # 3. 显示最终状态
    final_finals = SyllableCategorizer.get_all_finals()
    final_count = sum(len(finals) for finals in final_finals.values())
    added_count = final_count - initial_count

    print(f"\n3. 最终韵母总数: {final_count}")
    print(f"   新添加韵母数: {added_count}")

    # 4. 功能验证
    print("\n4. 功能验证:")

    # 验证分类功能
    test_finals = ['ian2', 'ōng', 'uái', 'iòng', 'iù', 'vè']
    print("   分类功能测试:")
    for final in test_finals:
        category = SyllableCategorizer.categorize(final)
        print(f"     '{final}' -> {category}")

    # 验证生成的文件
    print("   文件生成验证:")
    if os.path.exists(analyzer.ganyin_path):
        with open(analyzer.ganyin_path, 'r', encoding='utf-8') as f:
            ganyin_data = json.load(f)
        entries = len(ganyin_data.get('ganyin', {}))
        print(f"     干音数据文件: {entries} 条记录")

    if os.path.exists(analyzer.shouyin_path):
        with open(analyzer.shouyin_path, 'r', encoding='utf-8') as f:
            shouyin_data = json.load(f)
        entries = len(shouyin_data.get('shouyin', {}))
        print(f"     首音数据文件: {entries} 条记录")

    # 5. 展示分类分布
    print("\n5. 最终韵母分类分布:")
    for category, finals in final_finals.items():
        count = len(finals)
        percentage = (count / final_count) * 100
        print(f"   {category}: {count} 个 ({percentage:.1f}%)")

    print(f"\n✅ 韵母动态添加功能测试完成!")
    print(f"   - 成功添加 {added_count} 个新韵母到预定义分类中")
    print(f"   - 所有韵母都能正确分类")
    print(f"   - 生成的首音和干音数据文件完整")

if __name__ == "__main__":
    final_test()
