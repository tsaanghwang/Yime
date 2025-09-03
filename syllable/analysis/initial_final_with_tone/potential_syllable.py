import json
import os
from pathlib import Path

# 声调符号映射
TONE_MARKS = {
    "1": "̄",  # 降调
    "2": "́",  # 升调
    "3": "̌",  # 低调
    "4": "̀",  # 降调
    "5": ""   # 轻声
}

# 标注调号位置优先级顺序
TONE_POSITION_PRIORITY = ['a', 'o', 'e', 'i', 'u', 'ü']

# 特殊音质列表
SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]


def normalize_pinyin(pinyin_with_tone: str) -> str:
    """
    将用数字标调的拼音转换为用调号标调的拼音
    参考 pinyin_normalizer.py 的实现

    参数:
        pinyin_with_tone: 用数字标调的拼音 (如 "zhong1")

    返回:
        用调号标调的拼音 (如 "zhōng")
    """
    if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
        return pinyin_with_tone  # 没有调号，直接返回

    tone_num = pinyin_with_tone[-1]
    pinyin = pinyin_with_tone[:-1].replace("v", "ü")  # 处理v->ü转换

    # 检查是否是特殊音质拼音
    for sq in SPECIAL_QUALITIES:
        if pinyin == sq:
            return normalize_special_pinyin(sq, tone_num)

    # 按优先级查找元音位置
    for vowel in TONE_POSITION_PRIORITY:
        if vowel in pinyin:
            index = pinyin.index(vowel)
            return pinyin[:index] + vowel + TONE_MARKS[tone_num] + pinyin[index+1:]

    # 没有找到可标调的元音，返回不带调号的拼音
    return pinyin


def normalize_special_pinyin(syllabic_quality: str, tone: str) -> str:
    """
    标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）

    参数:
        syllabic_quality: 析出声调的特殊音节的音质
        tone: 声调数字（1-5）

    返回:
        用调号标调的拼音
    """
    if tone not in TONE_MARKS:
        return syllabic_quality

    if syllabic_quality == "ê":
        return "ê" + TONE_MARKS[tone]
    elif syllabic_quality in ["m", "n"]:
        return syllabic_quality + TONE_MARKS[tone]
    elif syllabic_quality == "ng":
        return "n" + TONE_MARKS[tone] + "g"  # 标调在n上
    elif syllabic_quality in ["hm", "hn", "hng"]:
        if syllabic_quality == "hng":
            return "h" + "n" + TONE_MARKS[tone] + "g"
        return "h" + syllabic_quality[1] + TONE_MARKS[tone]
    return syllabic_quality


def generate_potential_syllables():
    # 使用绝对路径
    current_dir = Path(__file__).parent.absolute()
    input_file = current_dir / "initial_final_with_tone.json"

    with open(input_file, "r", encoding="utf-8") as f:
        actual_syllables = json.load(f)

    potential_syllables = {}

    # 遍历每个声母及其对应的韵母
    for initial, final_with_tone_items in actual_syllables.items():
        potential_final_with_tone_items = {}

        # 检查每个韵母的声调是否完整
        for numbered_final_with_tone, marked_final_with_tone in final_with_tone_items.items():
            # 提取韵母基和声调数字
            final = numbered_final_with_tone[:-1]
            tone = numbered_final_with_tone[-1]

            # 检查该韵母基的所有可能声调
            all_tones = {f"{final}{t}": normalize_pinyin(f"{final}{t}")
                         for t in TONE_MARKS.keys()}

            # 检查是否已经存在所有声调变体
            existing_tones = {k: v for k, v in final_with_tone_items.items()
                              if k.startswith(final)}

            # 如果已经存在所有变体或不存在任何变体，则跳过
            if set(existing_tones.keys()) == set(all_tones.keys()) or not existing_tones:
                continue

            # 否则，添加缺失的声调变体
            for tone_num in TONE_MARKS:
                potential_numbered_final_with_tone = f"{final}{tone_num}"
                if potential_numbered_final_with_tone not in final_with_tone_items:
                    potential_final_with_tone_items[potential_numbered_final_with_tone] = all_tones[potential_numbered_final_with_tone]

        if potential_final_with_tone_items:
            potential_syllables[initial] = potential_final_with_tone_items

    # 写入潜在音节文件
    output_file = current_dir / "potential_syllables.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(potential_syllables, f, ensure_ascii=False, indent=2)

    # 合并实际音节和潜在音节
    all_syllables = {}

    # 添加实际音节
    for initial, final_with_tone_items in actual_syllables.items():
        if initial not in all_syllables:
            all_syllables[initial] = {}
        all_syllables[initial].update(final_with_tone_items)

    # 添加潜在音节
    for initial, final_with_tone_items in potential_syllables.items():
        if initial not in all_syllables:
            all_syllables[initial] = {}
        all_syllables[initial].update(final_with_tone_items)

    # 写入合并后的文件
    merged_file = current_dir / "all_possible_syllables.json"
    with open(merged_file, "w", encoding="utf-8") as f:
        json.dump(all_syllables, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    generate_potential_syllables()
