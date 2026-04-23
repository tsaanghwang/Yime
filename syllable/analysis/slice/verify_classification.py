#!/usr/bin/env python3
"""
验证新添加韵母的分类是否合理
"""
import importlib
from typing import Any

try:
    from .ganyin_categorizer import GanyinCategorizer
except ImportError:
    GanyinCategorizer = importlib.import_module('ganyin_categorizer').GanyinCategorizer


NEW_FINALS = ['ian', 'iong', 'iu', 'ong', 'ua', 'uai', 'ue', 'ui', 'un', 'v', 'van', 've']

EXPECTED_CATEGORIES = {
    'ian': '三质干音',
    'iong': '三质干音',
    'iu': '三质干音',
    'ong': '三质干音',
    'ua': '后长干音',
    'uai': '三质干音',
    'ue': '后长干音',
    'ui': '三质干音',
    'un': '三质干音',
    'v': '单质干音',
    'van': '三质干音',
    've': '后长干音',
}


def collect_classification_results() -> dict[str, Any]:
    """收集新增韵母分类验证结果，供脚本输出和测试复用。"""
    actual_categories = {final: GanyinCategorizer.categorize(final) for final in NEW_FINALS}
    mismatches: dict[str, dict[str, str]] = {
        final: {
            'expected': EXPECTED_CATEGORIES[final],
            'actual': actual_categories[final],
        }
        for final in NEW_FINALS
        if actual_categories[final] != EXPECTED_CATEGORIES[final]
    }

    all_finals = GanyinCategorizer.get_all_finals()
    total = sum(len(finals) for finals in all_finals.values())
    category_stats: dict[str, dict[str, float]] = {
        category: {
            'count': float(len(finals)),
            'percentage': (len(finals) / total) * 100 if total else 0,
        }
        for category, finals in all_finals.items()
    }

    return {
        'new_finals': NEW_FINALS,
        'expected_categories': EXPECTED_CATEGORIES,
        'actual_categories': actual_categories,
        'mismatches': mismatches,
        'all_finals': all_finals,
        'category_stats': category_stats,
        'total': total,
    }


def analyze_new_finals() -> dict[str, Any]:
    """分析新添加韵母的分类合理性。"""
    results = collect_classification_results()
    print("=== 验证新添加韵母分类的合理性 ===")

    print("新添加的韵母及其分类:")
    for final in results['new_finals']:
        category = results['actual_categories'][final]
        print(f"  '{final}' -> {category}")

        expected = results['expected_categories'][final]

        if category == expected:
            print(f"    ✓ 分类正确")
        else:
            print(f"    ⚠ 预期: {expected}, 实际: {category}")

    print("\n=== 韵母分类统计 ===")
    for category, stats in results['category_stats'].items():
        count = stats['count']
        percentage = stats['percentage']
        print(f"{category}: {count} 个韵母 ({percentage:.1f}%)")

    print(f"\n总韵母数量: {results['total']}")
    return results


if __name__ == "__main__":
    analyze_new_finals()
