# syllable/analysis/initial_final_with_tone/initial_final.py
import json
import os
from collections import defaultdict
import unicodedata
import re


def remove_tone(final_with_tone):
    """只去除韵母中的声调标记，不改变 ê、ü 等本身字符"""
    if not final_with_tone:
        return final_with_tone

    # 针对 y 开头的音节，将值中的 'u' 替换为 'ü'（调号不变）
    if final_with_tone and final_with_tone[0] == 'y':
        # 将字符串转换为列表以便修改
        chars = list(final_with_tone)
        # 检查 y 后是否跟着 u
        if len(chars) > 1 and chars[1] == 'u':
            # 将 u 替换为 ü
            chars[1] = 'ü'
            # 重新组合为字符串
            final_with_tone = ''.join(chars)

    # 只去除组合用声调符号（Mn），但保留 ê、ü 等本身字符
    def is_tone_mark(c):
        # 只去除声调符号，不去除本身带变音符的字母
        return unicodedata.category(c) == 'Mn' and c not in ['\u0308', '\u0302']

    return ''.join(
        c for c in unicodedata.normalize('NFD', final_with_tone)
        if not is_tone_mark(c)
    )


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

        # 处理每个 initial 和对应的 final_with_tone_items
        for initial, final_with_tone_items in initial_final_with_tone_data.items():
            # 声母部分：以键为值
            result["initials"][initial] = initial

            # 处理每个 final_with_tone
            for final_with_tone_key, final_with_tone_value in final_with_tone_items.items():
                # 键保持原样
                final_key = final_with_tone_key

                # 只对值部分去除声调得到韵母
                final_value = remove_tone(final_with_tone_value)

                # 特殊处理：只有特殊声母的i韵母才用"_i"
                if (initial in special_initials and
                    final_with_tone_key.startswith("i") and
                        # 只处理单韵母i
                        len(final_with_tone_key.replace(final_with_tone_key[-1], '') if final_with_tone_key[-1].isdigit() else final_with_tone_key) == 1):
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
