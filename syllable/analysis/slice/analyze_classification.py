#!/usr/bin/env python3
"""
分析韵母分类的合理性
"""

from ganyin_categorizer import GanyinCategorizer

def analyze_classification_logic():
    """分析韵母分类的合理性"""
    print("=== 分析韵母分类的合理性 ===")

    # 首先运行分析以确保韵母被添加
    analyzer = GanyinCategorizer()

    print("\n各类韵母分析:")
    all_finals = GanyinCategorizer.get_all_finals()

    # 分析单质韵母
    print("\n1. 单质韵母 (应该是单个音质成分):")
    single_quality = sorted(all_finals["单质韵母"])
    for final in single_quality:
        if final.startswith('_'):
            print(f"   '{final}' - 舌尖音占位符")
        elif len(final) == 1:
            print(f"   '{final}' - 单个字符韵母")
        elif len(final) == 2:
            print(f"   '{final}' - 短复合韵母")
        else:
            print(f"   '{final}' - 可能误分类")

    # 分析前长韵母
    print("\n2. 前长韵母 (通常以a/e/o开头或以n/ng结尾但不以i/u/ü开头):")
    front_long = sorted(all_finals["前长韵母"])
    for final in front_long:
        if final[0] in 'aeo':
            print(f"   '{final}' - 以 {final[0]} 开头")
        elif final.endswith(('n', 'ng')):
            print(f"   '{final}' - 以鼻音结尾")
        else:
            print(f"   '{final}' - 其他模式")

    # 分析后长韵母
    print("\n3. 后长韵母 (通常以i/u/ü开头的复合韵母):")
    back_long = sorted(all_finals["后长韵母"])
    for final in back_long:
        if final[0] in 'iuü':
            print(f"   '{final}' - 以 {final[0]} 开头")
        else:
            print(f"   '{final}' - 特殊情况")

    # 分析三质韵母
    print("\n4. 三质韵母 (通常是长复合韵母，包含三个音质成分):")
    triple_quality = sorted(all_finals["三质韵母"])
    for final in triple_quality:
        print(f"   '{final}' - 长度: {len(final)}")

    # 统计分析
    print("\n=== 统计分析 ===")
    total = sum(len(finals) for finals in all_finals.values())

    for category, finals in all_finals.items():
        count = len(finals)
        avg_length = sum(len(f) for f in finals) / count if count > 0 else 0
        print(
            f"{category}: {count} 个韵母 ({count/total*100:.1f}%), 平均长度: {avg_length:.1f}")


if __name__ == "__main__":
    analyze_classification_logic()