
"""
提取乐音类片音
功能：从被切分成乐音序列的干音中提取乐音类片音
输入：干音数据（JSON格式）
输出：提取的乐音类片音数据（JSON格式）
"""

import json
from pathlib import Path
from collections import OrderedDict

def extract_yueyin(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    yueyin_map = {}

    # 处理所有干音类别
    for category in data.values():
        for sound_data in category.values():
                # 提取呼音、主音和末音
                for sound_type in ["呼音", "主音", "末音"]:
                    sound = sound_data[sound_type]

                    # 处理可能的分隔符"/"
                    for variant in sound.split("/"):
                        # 提取音素和声调
                        if "˥" in variant:
                            pitch = "5"
                            quality = variant.split("˥")[0]
                        elif "˦" in variant:
                            pitch = "4"
                            quality = variant.split("˦")[0]
                        elif "˧" in variant:
                            pitch = "3"
                            quality = variant.split("˧")[0]
                        elif "˨" in variant:
                            pitch = "2"
                            quality = variant.split("˨")[0]
                        elif "˩" in variant:
                            pitch = "1"
                            quality = variant.split("˩")[0]
                        else:
                            continue  # 忽略无声调的音素

                        # 构建乐音类片音映射
                        key = f"{quality}˥" if pitch == "5" else \
                              f"{quality}˦" if pitch == "4" else \
                              f"{quality}˧" if pitch == "3" else \
                              f"{quality}˨" if pitch == "2" else \
                              f"{quality}˩"

                        value = f"{quality}{pitch}"
                        yueyin_map[key] = value

    # ---- moved sorting here: 定义音质优先级顺序并排序 ----
    priority_order = [
        "i", "ɪ", "u", "ᴜ", "ʏ", "y", "ᴀ", "a", "æ", "ɑ", "o", "ɤ", "𐞑",
        "ᴇ", "e", "ə", "ᵊ", "ʅ", "ɿ", "ɚ", "m", "n", "ŋ"
    ]
    quality_priority = {quality: idx for idx, quality in enumerate(priority_order)}

    # 如果 yueyin_map 为空，sorted_items 设为空列表，避免未定义错误
    if yueyin_map:
        sorted_items = sorted(
            yueyin_map.items(),
            key=lambda x: (
                quality_priority.get(x[1][:-1], len(priority_order)),  # 按音质优先级排序
                -int(x[1][-1])  # 同音质内部按音高降序
            )
        )
    else:
        sorted_items = []

    # 转换为有序字典
    ordered_yueyin = OrderedDict(sorted_items)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(ordered_yueyin, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    base_dir = Path(__file__).parent
    input_path = base_dir / "yinyuan" / "ganyin_to_pianyin_sequence.json"
    output_path = base_dir / "yinyuan" / "pitched_pianyin.json"
    extract_yueyin(input_path, output_path)

    # 添加提示信息
    with open(output_path, "r", encoding="utf-8") as f:
        yueyin_data = json.load(f)
    print(f"乐音类片音数据已生成，保存至: {output_path}")
    print(f"共提取 {len(yueyin_data)} 条乐音类片音条目")
