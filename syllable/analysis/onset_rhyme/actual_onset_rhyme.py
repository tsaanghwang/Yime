# syllable/analysis/onset_rhyme/actual_onset_rhyme.py
import json
import os
from collections import defaultdict


def remove_tone(rhyme):
    """去掉韵母中的声调数字"""
    if rhyme and rhyme[-1].isdigit():
        return rhyme[:-1]
    return rhyme


def main():
    # 输入文件路径
    input_path = os.path.join(
        os.path.dirname(__file__),
        'onset_rhyme.json'
    )

    # 输出文件路径
    output_path = os.path.join(
        os.path.dirname(__file__),
        'actual_onset_rhyme.json'
    )

    try:
        # 读取 onset_rhyme.json 文件
        with open(input_path, 'r', encoding='utf-8') as f:
            onset_rhyme_data = json.load(f)

        # 初始化结果字典
        result = {
            "onset": set(),
            "rhyme": set()
        }

        # 处理每个 onset 和对应的 rhymes
        for onset, rhymes in onset_rhyme_data.items():
            result["onset"].add(onset)

            # 处理每个 rhyme，去掉声调
            for rhyme in rhymes:
                no_tone_rhyme = remove_tone(rhyme)
                if no_tone_rhyme:  # 确保不是空字符串
                    result["rhyme"].add(no_tone_rhyme)

        # 将集合转换为排序后的列表
        result["onset"] = sorted(result["onset"])
        result["rhyme"] = sorted(result["rhyme"])

        # 写入输出文件
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        # 统计并输出数量
        onset_count = len(result["onset"])
        rhyme_count = len(result["rhyme"])
        print(f"成功生成 actual_onset_rhyme.json 文件")
        print(f"声母总数: {onset_count}")
        print(f"韵母总数: {rhyme_count}")
        return True

    except Exception as e:
        print(f"Error processing onset_rhyme data: {e}")
        return False


if __name__ == "__main__":
    main()
