"""
转换拼音格式
功能：将带数字调号的拼音转换为带声调符号的标准拼音

处理流程：
1. 读取JSON文件，取出每个键值对象（item）的键和值（均为带数字调号的拼音）
2. 判断每个键值对象（item）的键和值是否相同
3. 如果相同，不作处理，保留原值；如果不同，则以该键值对象（item）的键为值，并记录有几个不同
4. 给每个键值对象（item）值（带数字调号的拼音）添加声调符号，亦即将其转换为带声调符号的拼音
5. 检查是否有特殊音质（"ê", "m", "n", "ng", "hm", "hn", "hng"）与声调（"1", "2", "3", "4", "5"）构成的音节
    - 如果有，则将其值转换为带声调符号的标准拼音
    - 如果没有，则追加所缺拼音（键），并以键为值且将其值转换为带声调符号的标准拼音
6. 将结果以JSON格式保存到指定文件
"""

import json
from pathlib import Path
from typing import Dict, Tuple

# 特殊音质列表
SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]
# 所有可能的声调
TONES = ["1", "2", "3", "4", "5"]

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


def normalize_special_pinyin(syllable: str, tone: str) -> str:
    """
    标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）

    参数:
        syllable: 特殊音质音节（不带声调）
        tone: 声调数字（1-5）

    返回:
        带声调符号的标准拼音
    """
    if not tone in TONE_MARKS:
        return syllable

    if syllable == "ê":
        return "ê" + TONE_MARKS[tone]
    elif syllable in ["m", "n"]:
        return syllable + TONE_MARKS[tone]
    elif syllable == "ng":
        return "n" + TONE_MARKS[tone] + "g"  # 标调在n上
    elif syllable in ["hm", "hn", "hng"]:
        # 标调在m或n上
        if syllable == "hng":
            return "h" + "n" + TONE_MARKS[tone] + "g"
        return "h" + syllable[1] + TONE_MARKS[tone]  # hm → h + m̄, hn → h + ń
    return syllable


def supplement_special_pinyin(pinyin_dict: Dict[str, str], input_file: Path) -> None:
    """
    补充缺失的特殊音质拼音

    参数:
        pinyin_dict: 待补充的拼音字典
        input_file: 输入文件路径
    """
    # 查看原始输入文件中是否包含这些特殊拼音
    with open(input_file) as f:
        original_dict = json.load(f)

    special_pinyins = [f"{sq}{tone}" for sq in SPECIAL_QUALITIES for tone in TONES]
    missing = [p for p in special_pinyins if p not in original_dict]
    print(f"新增补充的特殊拼音数量: {len(missing)}")

def normalize_pinyin(pinyin_with_tone: str) -> str:
    """
    将带数字调号的拼音转换为带声调符号的标准拼音

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


def process_pinyin_dict(input_dict: Dict[str, str], input_file: Path) -> Tuple[Dict[str, str], int]:
    normalized_dict = {}
    mismatch_count = 0

    for key, value in input_dict.items():
        if key != value:
            mismatch_count += 1
            # 明确以键为值进行标准化
            normalized_dict[key] = normalize_pinyin(key)
        else:
            # 对于键值相同的也统一使用key进行标准化
            normalized_dict[key] = normalize_pinyin(key)

    # 补充特殊拼音
    supplement_special_pinyin(normalized_dict, input_file)

    return normalized_dict, mismatch_count

def main():
    """主处理函数"""
    # 定义输入输出文件路径
    script_dir = Path(__file__).parent.absolute()
    input_file = script_dir / "pinyin.json"
    output_file = script_dir / "pinyin_normalized.json"

    try:
        print(f"正在读取输入文件: {input_file}")
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        print("正在处理拼音字典...")
        normalized_dict, mismatch_count = process_pinyin_dict(pinyin_dict, input_file)

        print(f"正在写入输出文件: {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(normalized_dict, f, ensure_ascii=False, indent=2)

        print(f"拼音标准化完成，结果已保存到: {output_file}")
        print(f"共处理 {len(normalized_dict)} 个拼音，其中 {mismatch_count} 个键值不匹配")

    except FileNotFoundError:
        print(f"错误: 输入文件 {input_file} 不存在")
    except json.JSONDecodeError:
        print(f"错误: 输入文件 {input_file} 不是有效的JSON格式")
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")
        raise


if __name__ == "__main__":
    main()
