# syllable/analysis/initial_final_with_tone/initial_final.py
import json
import os
from collections import defaultdict


def remove_tone(final_with_tone):
    """从韵母中去除所有声调标记"""
    if not final_with_tone:
        return final_with_tone

    # 定义所有可能的声调标记
    tone_marks = [
        '̄', '́', '̌', '̀',  # 基本声调符号
        '̂', '̇', '̈', '̊',  # 其他可能的变音符号
        'ń', 'ň', 'ǹ', 'ḿ',  # 带声调的字母
        'ế', 'ề', 'ê',  # 特殊拼音字符
        '1', '2', '3', '4', '5'  # 数字声调
    ]

    # 特殊字符映射表
    special_char_map = {
        'ń': 'n',
        'ň': 'n',
        'ǹ': 'n',
        'ḿ': 'm',
        'ế': 'e',
        'ề': 'e',
        'ê': 'e'
    }

    # 先去除数字声调
    if final_with_tone[-1].isdigit():
        final_with_tone = final_with_tone[:-1]

    # 处理特殊字符
    for char, replacement in special_char_map.items():
        final_with_tone = final_with_tone.replace(char, replacement)

    # 处理基本声调符号
    for mark in tone_marks:
        final_with_tone = final_with_tone.replace(mark, '')

    return final_with_tone


def main():
    # 输入文件路径
    input_path = os.path.join(
        os.path.dirname(__file__),
        'initial_final_with_tone.json'
    )

    # 输出文件路径
    output_path = os.path.join(
        os.path.dirname(__file__),
        'initial_final.json'
    )

    try:
        # 读取 initial_final_with_tone.json 文件
        with open(input_path, 'r', encoding='utf-8') as f:
            initial_final_with_tone_data = json.load(f)

        # 初始化结果字典
        result = {
            "initials": {},
            "finals": set()  # 使用集合来自动去重
        }

        # 特殊声母列表
        special_initials = ["z", "c", "s", "zh", "ch", "sh", "r"]

        # 特殊韵母列表 (hm -> m, hn -> n, hng -> ng)
        special_finals_map = {
            "hm": "m",
            "hn": "n",
            "hng": "ng"
        }

        # 处理每个 initial 和对应的 final_with_tone_items
        for initial, final_with_tone_items in initial_final_with_tone_data.items():
            # 声母部分：以键为值
            result["initials"][initial] = initial

            # 处理每个 final_with_tone
            for final_with_tone_key, final_with_tone_value in final_with_tone_items.items():
                # 检查是否是特殊韵母 (hm, hn, hng)
                if final_with_tone_key in special_finals_map:
                    result["finals"].add(
                        special_finals_map[final_with_tone_key])
                    continue

                # 从键中去除声调得到韵母
                final_key = remove_tone(final_with_tone_key)

                # 从值中去除声调得到韵母
                final_value = remove_tone(final_with_tone_value)

                # 特殊处理：只有特殊声母的i韵母才用"_i"
                if (initial in special_initials and
                    final_with_tone_key.startswith("i") and
                        len(remove_tone(final_with_tone_key)) == 1):  # 只处理单韵母i
                    result["finals"].add("_i")  # 特殊声母对应的形式
                    result["finals"].add("i")    # 普通形式
                else:
                    # 普通韵母处理
                    if final_key and final_value:
                        # 确保只添加去除声调后的韵母
                        result["finals"].add(final_value)

        # 将集合转换为列表并排序
        result["finals"] = sorted(list(result["finals"]))

        # 写入输出文件
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        # 统计并输出数量
        initial_count = len(result["initials"])
        final_count = len(result["finals"])
        print(f"成功生成 initial_final.json 文件")
        print(f"声母总数: {initial_count}")
        print(f"韵母总数: {final_count}")
        return True

    except Exception as e:
        print(f"Error processing initial_final_with_tone data: {e}")
        return False


if __name__ == "__main__":
    main()
