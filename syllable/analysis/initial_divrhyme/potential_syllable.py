import json
import os
from pathlib import Path

# 声调符号映射
TONE_MARKS = {
    "1": "̄",  # 高平调
    "2": "́",  # 升调
    "3": "̌",  # 低平调
    "4": "̀",  # 降调
    "5": ""   # 轻声
}

# 元音优先级顺序（用于确定标调位置）
VOWEL_PRIORITY = ['a', 'o', 'e', 'ü', 'i', 'u']

# 特殊音质列表
SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]


def normalize_pinyin(pinyin_with_tone: str) -> str:
    """
    将带数字调号的拼音转换为带声调符号的标准拼音
    参考 pinyin_normalizer.py 的实现

    参数:
        pinyin_with_tone: 带数字调号的拼音 (如 "zhong1")

    返回:
        带声调符号的标准拼音 (如 "zhōng")
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
    for vowel in VOWEL_PRIORITY:
        if vowel in pinyin:
            index = pinyin.index(vowel)
            return pinyin[:index] + vowel + TONE_MARKS[tone_num] + pinyin[index+1:]

    # 没有找到可标调的元音，返回不带调号的拼音
    return pinyin


def normalize_special_pinyin(syllable: str, tone: str) -> str:
    """
    标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）

    参数:
        syllable: 特殊音质音节（不带声调）
        tone: 声调数字（1-5）

    返回:
        带声调符号的标准拼音
    """
    if tone not in TONE_MARKS:
        return syllable

    if syllable == "ê":
        return "ê" + TONE_MARKS[tone]
    elif syllable in ["m", "n"]:
        return syllable + TONE_MARKS[tone]
    elif syllable == "ng":
        return "n" + TONE_MARKS[tone] + "g"  # 标调在n上
    elif syllable in ["hm", "hn", "hng"]:
        if syllable == "hng":
            return "h" + "n" + TONE_MARKS[tone] + "g"
        return "h" + syllable[1] + TONE_MARKS[tone]
    return syllable


def generate_potential_syllables():
    # 使用绝对路径
    current_dir = Path(__file__).parent.absolute()
    input_file = current_dir / "initial_divrhyme.json"

    with open(input_file, "r", encoding="utf-8") as f:
        actual_syllables = json.load(f)

    potential_syllables = {}

    # 遍历每个声母及其对应的韵母
    for initial, rhymes in actual_syllables.items():
        potential_rhymes = {}

        # 检查每个韵母的声调是否完整
        for numbered_rhyme, marked_rhyme in rhymes.items():
            # 提取韵母基和声调数字
            rhyme_base = numbered_rhyme[:-1]
            tone = numbered_rhyme[-1]

            # 检查该韵母基的所有可能声调
            all_tones = {f"{rhyme_base}{t}": normalize_pinyin(f"{rhyme_base}{t}")
                         for t in TONE_MARKS.keys()}

            # 检查是否已经存在所有声调变体
            existing_tones = {k: v for k, v in rhymes.items()
                              if k.startswith(rhyme_base)}

            # 如果已经存在所有变体或不存在任何变体，则跳过
            if set(existing_tones.keys()) == set(all_tones.keys()) or not existing_tones:
                continue

            # 否则，添加缺失的声调变体
            for tone_num in TONE_MARKS:
                potential_num_rhyme = f"{rhyme_base}{tone_num}"
                if potential_num_rhyme not in rhymes:
                    potential_rhymes[potential_num_rhyme] = all_tones[potential_num_rhyme]

        if potential_rhymes:
            potential_syllables[initial] = potential_rhymes

    # 写入潜在音节文件
    output_file = current_dir / "potential_syllables.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(potential_syllables, f, ensure_ascii=False, indent=2)

    # 合并实际音节和潜在音节
    all_syllables = {}

    # 添加实际音节
    for initial, rhymes in actual_syllables.items():
        if initial not in all_syllables:
            all_syllables[initial] = {}
        all_syllables[initial].update(rhymes)

    # 添加潜在音节
    for initial, rhymes in potential_syllables.items():
        if initial not in all_syllables:
            all_syllables[initial] = {}
        all_syllables[initial].update(rhymes)

    # 写入合并后的文件
    merged_file = current_dir / "all_possible_syllables.json"
    with open(merged_file, "w", encoding="utf-8") as f:
        json.dump(all_syllables, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    generate_potential_syllables()
