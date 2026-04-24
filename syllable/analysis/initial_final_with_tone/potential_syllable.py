import json
from pathlib import Path

from utils.pinyin_normalizer import normalize_one, PinyinNormalizer


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
            all_tones = {f"{final}{tone}": normalize_one(f"{final}{tone}")
                         for tone in PinyinNormalizer.TONES}

            # 检查是否已经存在所有声调变体
            existing_tones = {k: v for k, v in final_with_tone_items.items()
                              if k.startswith(final)}

            # 如果已经存在所有变体或不存在任何变体，则跳过
            if set(existing_tones.keys()) == set(all_tones.keys()) or not existing_tones:
                continue

            # 否则，添加缺失的声调变体
            for tone_num in PinyinNormalizer.TONES:
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
