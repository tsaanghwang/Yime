# syllable/analysis/initial_final_with_tone/initial_final.py
import json
import os
from collections import defaultdict


def remove_tone(final_with_tone):
    """从等韵（干音）中去除声调数字或符号"""
    # 先去除末尾的数字
    if final_with_tone and final_with_tone[-1].isdigit():
        final_with_tone = final_with_tone[:-1]

    # 去除声调符号
    tone_marks = ['̄', '́', '̌', '̀']
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
            "finals": {}
        }

        # 特殊声母列表
        special_initials = ["z", "c", "s", "zh", "ch", "sh", "r"]

        # 处理每个 initial 和对应的 final_with_tone_items
        for initial, final_with_tone_items in initial_final_with_tone_data.items():
            # 声母部分：以键为值
            result["initials"][initial] = initial

            # 处理每个 final_with_tone
            for final_with_tone_key, final_with_tone_value in final_with_tone_items.items():
                # 从键中去除声调得到韵母
                final_key = remove_tone(final_with_tone_key)

                # 从值中去除声调得到韵母
                final_value = remove_tone(final_with_tone_value)

                # 特殊处理：只有特殊声母的i韵母才用"_i"
                if (initial in special_initials and
                    final_with_tone_key.startswith("i") and
                        len(remove_tone(final_with_tone_key)) == 1):  # 只处理单韵母i
                    # 添加两种形式
                    result["finals"]["_i"] = "_i"  # 特殊声母对应的形式
                    result["finals"]["i"] = "i"    # 普通形式
                else:
                    # 普通韵母处理
                    if final_key and final_value:
                        result["finals"][final_key] = final_value

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
