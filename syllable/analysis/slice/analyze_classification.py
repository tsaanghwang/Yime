#!/usr/bin/env python3
"""
分析韵母分类的合理性
"""

from ganyin_categorizer import GanyinCategorizer

def analyze_classification_logic():
    """分析韵母分类的合理性"""
    print("=== 分析韵母分类的合理性 ===")

    # 首先运行分析以确保韵母被添加
    analyzer = ()

    print("\n各类韵母分析:")
    all_finals = GanyinCategorizer.get_all_finals()

    category_notes = {
        "单质韵母": "当前分类表将其视为单一音质或约定视作单质的韵母。",
        "前长韵母": "当前分类表将其视为以前部非高元音起头的长韵母。",
        "后长韵母": "当前分类表将其视为以高元音起头的二合韵母。",
        "三质韵母": "当前分类表将其视为包含三个音质层次或按系统约定归入三质的韵母。",
    }

    for index, category in enumerate(["单质韵母", "前长韵母", "后长韵母", "三质韵母"], start=1):
        print(f"\n{index}. {category} ({category_notes[category]})")
        for final in GanyinCategorizer.sort_finals_by_category({category: all_finals[category]})[category]:
            print(f"   '{final}'")

    # 统计分析
    print("\n=== 统计分析 ===")
    total = sum(len(finals) for finals in all_finals.values())

    for category, finals in all_finals.items():
        count = len(finals)
        avg_length = sum(len(f) for f in finals) / count if count > 0 else 0
        print(
            f"{category}: {count} 个韵母 ({count/total*100:.1f}%), 平均字符长度: {avg_length:.1f}")

    print(f"韵母总量(含输入法拼式)共有: {total}个")

if __name__ == "__main__":
    analyze_classification_logic()
