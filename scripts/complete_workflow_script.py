#!/usr/bin/env python3
"""
完整测试韵母动态添加功能
"""
import  sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from ganyin_categorizer import GanyinCategorizer
from syllable_analyzer import YinjieAnalyzer
import json
import os


def test_complete_workflow():
    """测试完整的工作流程"""
    print("=== 完整工作流程测试 ===")

    # 1. 显示初始状态
    print("1. 初始韵母分类状态:")
    initial_finals = GanyinCategorizer.get_all_finals()
    for category, finals in initial_finals.items():
        print(f"   {category}: {len(finals)} 个")

    # 2. 执行分析过程
    print("\n2. 执行分析过程...")
    analyzer = YinjieAnalyzer(__file__)

    # 检查输入文件是否存在
    if not os.path.exists(analyzer.input_path):
        print(f"   输入文件不存在: {analyzer.input_path}")
        return

    # 执行分析
    success = analyzer.analyze_and_save()
    if success:
        print("   分析成功完成")
    else:
        print("   分析失败")
        return

    # 3. 显示更新后状态
    print("\n3. 更新后韵母分类状态:")
    updated_finals = GanyinCategorizer.get_all_finals()
    for category, finals in updated_finals.items():
        print(f"   {category}: {len(finals)} 个")

    # 4. 测试新韵母分类
    print("\n4. 测试新韵母分类:")
    new_finals = ['ian', 'iong', 'iu', 'ong', 'ua',
                  'uai', 'ue', 'ui', 'un', 'v', 'van', 've']

    for final in new_finals:
        category = GanyinCategorizer.categorize(final)
        in_any_set = any(final in finals for finals in updated_finals.values())
        print(f"   '{final}' -> {category} (在集合中: {in_any_set})")

    # 5. 验证生成的文件
    print("\n5. 验证生成的文件:")
    if os.path.exists(analyzer.ganyin_path):
        with open(analyzer.ganyin_path, 'r', encoding='utf-8') as f:
            ganyin_data = json.load(f)
        ganyin_count = len(ganyin_data.get('ganyin', {}))
        print(f"   干音数据: {ganyin_count} 项")

        # 检查一些新韵母是否在生成的数据中
        ganyin_finals = ganyin_data.get('ganyin', {})
        test_entries = ['ian1', 'iong1', 'ong1', 'ua1']
        for entry in test_entries:
            if entry in ganyin_finals:
                print(f"   ✓ 找到: {entry} -> {ganyin_finals[entry]}")
            else:
                print(f"   ✗ 未找到: {entry}")


if __name__ == "__main__":
    test_complete_workflow()
