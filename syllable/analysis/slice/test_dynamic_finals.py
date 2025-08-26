#!/usr/bin/env python3
"""
测试韵母动态添加功能
"""
import  sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from syllable_categorizer import SyllableCategorizer

def test_dynamic_finals():
    """测试韵母动态添加功能"""
    print("=== 测试韵母动态添加功能 ===")

    # 显示初始韵母分类状态
    print("初始韵母分类:")
    initial_finals = SyllableCategorizer.get_all_finals()
    for category, finals in initial_finals.items():
        print(f"  {category}: {len(finals)} 个韵母")

    # 测试新韵母添加
    new_test_finals = ['ian', 'ong', 'ua', 'uai', 'iu', 've', 'iong']

    print(f"\n测试添加新韵母: {new_test_finals}")
    added_count = 0

    for final in new_test_finals:
        if SyllableCategorizer._add_final_to_category(final):
            category = SyllableCategorizer.categorize(final)
            print(f"  '{final}' 添加到 {category}")
            added_count += 1
        else:
            category = SyllableCategorizer.categorize(final)
            print(f"  '{final}' 已存在于 {category}")

    print(f"\n成功添加 {added_count} 个新韵母")

    # 显示更新后的韵母分类状态
    print("\n更新后韵母分类:")
    updated_finals = SyllableCategorizer.get_all_finals()
    for category, finals in updated_finals.items():
        print(f"  {category}: {len(finals)} 个韵母")
        print(f"    {sorted(finals)}")

    # 测试分类功能
    print("\n=== 测试韵母分类功能 ===")
    test_cases = ['ian2', 'ōng', 'uá', 'uài', 'iū', 'vè', 'ióng']

    for final in test_cases:
        normalized = SyllableCategorizer._remove_tone_from_ganyin(final)
        category = SyllableCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")

if __name__ == "__main__":
    test_dynamic_finals()
