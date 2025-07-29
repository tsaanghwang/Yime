#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from ganyin import GanyinCategorizer

def test_categorization():
    print("=== 测试韵母分类功能 ===")
    
    # 测试示例
    samples = ["ī", "āi", "iā", "iāo"]
    
    for final in samples:
        normalized = GanyinCategorizer._normalize_final(final)
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")
        
        # 调试信息
        if category == "未知类型":
            print(f"  调试: 标准化结果 '{normalized}' 在各个集合中的检查:")
            print(f"    SINGLE_QUALITY_FINALS: {normalized in GanyinCategorizer.SINGLE_QUALITY_FINALS}")
            print(f"    FRONT_LONG_FINALS: {normalized in GanyinCategorizer.FRONT_LONG_FINALS}")
            print(f"    BACK_LONG_FINALS: {normalized in GanyinCategorizer.BACK_LONG_FINALS}")
            print(f"    TRIPLE_QUALITY_FINALS: {normalized in GanyinCategorizer.TRIPLE_QUALITY_FINALS}")
    
    print("\n=== 四类韵母数据 ===")
    all_finals = GanyinCategorizer.get_all_finals()
    for category, finals in all_finals.items():
        print(f"{category}: {sorted(finals)}")

if __name__ == "__main__":
    test_categorization()
