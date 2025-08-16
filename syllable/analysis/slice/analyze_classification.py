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
    print("\n1. 单质韵母 (根据音质（音标）判断只含单一音质成分):")
    priority_order = ['i', 'u', 'ü', 'v', 'a', 'o', 'e', 'ê', '_i', 'er', 'm', 'n', 'ng']  # 自定义优先级顺序
    single_quality = sorted(all_finals["单质韵母"],
                        key=lambda x: (
                            priority_order.index(x) if x in priority_order else len(priority_order)
                        ))
    for final in single_quality:
        if final.startswith('_'):
            print(f"   '{final}' - 带舌尖声母占位符的单质韵母")
        elif len(final) == 1 and final != 'v':
            print(f"   '{final}' - 用单个字符来表示的单质韵母")
        elif len(final) == 1 and final == 'v':
            print(f"   '{final}' - 微软输入法替代拼式单质韵母")
        elif len(final) == 2:
            print(f"   '{final}' - 用两个字符来表示的单质韵母")
        else:
            print(f"   '{final}' - 韵母分类错误")

    # 分析前长韵母
    print("\n2. 前长韵母 (以a/e/o而不以i/u/ü开头且韵母不是 ong 的二合韵母):")
    priority_order = ['i', 'o', 'u', 'n', 'ng']  # 自定义优先级顺序
    front_long = sorted(all_finals["前长韵母"],
                    key=lambda x: (
                        priority_order.index(x[1]) if len(x) > 1 and x[1] in priority_order else len(priority_order),  # 按自定义顺序排序
                        x[2] if len(x) > 2 else '',  # 然后按第三个字符排序
                        x[1] if len(x) > 1 else '',  # 然后按第二个字符排序
                        x[0]  # 最后按第一个字符排序
                    ))
    for final in front_long:
        if final[0] in 'aeo' and final[0] not in 'iuü' and final != 'ong':
            print(f"   '{final}' - 以非高舌位元音 {final[0]} 开头的二合韵母")
        else:
            print(f"   '{final}' - 韵母分类错误")

    # 分析后长韵母
    print("\n3. 后长韵母 (以i/u/ü开头的二合韵母):")
    priority_order = ['a', 'o', 'e', 'n', 'ng']  # 自定义优先级顺序
    back_long = sorted(all_finals["后长韵母"],
                    key=lambda x: (
                        priority_order.index(x[1]) if len(x) > 1 and x[1] in priority_order else len(priority_order),
                        x[2] if len(x) > 2 else '',
                        x[1] if len(x) > 1 else '',
                        0 if x[0] == 'i' else (1 if x[0] == 'u' else (2 if  x[0] == 'ü' else 3)),  # i>u>ü > v > 其他
                        x[0]
                    ))
    for final in back_long:
        if final[0] in 'iuü':
            print(f"   '{final}' - 以高位元音 {final[0]} 开头的二合韵母")
        elif final in ['in', 'un', 'ün', 'vn', 'ing', 'ung', 'ong', 'iong', 'yng', 'üng', 'vng']:
            print(f"   '{final}' - 由三质韵母脱落韵腹[ᵊ]或[𐞑]变成的后长韵母")
        elif final == 've' or 'vn':
            print(f"   '{final}' - 特殊情况：微软输入法替代拼式")
        else:
            print(f"   '{final}' - 韵母分类错误")

    # 分析三质韵母
    print("\n4. 三质韵母 (从形式上分析包含三个音质成分):")
    priority_order = ['ai', 'ei', 'i', 'ao', 'ou', 'u', 'an', 'en', 'n', 'ang', 'eng', 'ng', 'ong']  # 自定义优先级顺序
    triple_quality = sorted(all_finals["三质韵母"],
                    key=lambda x: (
                        priority_order.index(x[1:]) if len(x) > 1 and x[1:] in priority_order else len(priority_order),  # 按不含第一个字符的片段的优先级排序
                        x[2] if len(x) > 2 else '',  # 然后按第三个字符排序
                        x[1] if len(x) > 1 else '',  # 然后按第二个字符排序
                        0 if x[0] == 'i' else (1 if x[0] == 'u' else (2 if  x[0] == 'ü' else 3)),  # i>u>ü > v > 其他
                    ))
    for final in triple_quality:
        processed_final = final.replace('io', 'Y')
        if processed_final == 'Yu':  # 处理"iou"情况
            length = len(processed_final.replace('ng', 'N'))
            print(f"   '{final}' - 长度: {length}：正常三质韵母")
        else:
            length = len(processed_final.replace('ng', 'N'))
            if length == 2:
                if 'ng' in final:  # 检查是否包含'ng'
                    if final in ['ing', 'ong']:
                        print(f"   '{final}' - 韵腹[𐞑]经常脱落的三质韵母")
                    elif final in ['iong']:
                        print(f"   '{final}' - 韵腹[𐞑]经常脱落的三质韵母")
                    else:
                        print(f"   '{final}' - 韵腹[𐞑]经常脱落的三质韵母")
                else:
                    second_char = final[1] if len(final) > 1 else ''
                    if second_char in ['i', 'n']:
                        print(f"   '{final}' - 韵腹[ᵊ]经常脱落的三质韵母")
                    elif second_char in ['u']:
                        print(f"   '{final}' - 韵腹[𐞑]经常脱落的三质韵母")
                    else:
                        print(f"   '{final}' - 长度: {length}：正常三质韵母")
            else:
                print(f"   '{final}' - 长度: {length}：正常三质韵母")

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