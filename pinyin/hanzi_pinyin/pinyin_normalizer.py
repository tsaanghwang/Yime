"""
转换拼音格式
功能：将用数字标调的拼音转换为用调号标调的拼音

处理流程：
1. 加载拼音数据，字典结构为：{"用数字标调的拼音": "用数字标调的拼音"}
2. 核对每个条目的键和值是否相同
    - 如果相同，不作处理，保留原值
    - 如果不同，以键为值，并记录有多少键值不一致的条目
3. 检查是否有所有由特殊音质（"ê", "m", "n", "ng", "hm", "hn", "hng"）与声调（"1", "2", "3", "4", "5"）构成的音节
    - 如果都有，不作处理
    - 如果缺少其中某个音节，则以拼音为键且以键为值追加所缺条目
4.  将每个条目的值（用数字标调的拼音）转换为用调号标调的拼音
5.  将结果保存到指定文件中
"""

import json
from pathlib import Path
from typing import Dict, Tuple
from collections import OrderedDict

# 特殊音质列表
SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]
# 所有可能的声调
TONES = ["1", "2", "3", "4", "5"]

# 声调符号映射
TONE_MARKS = {
    "1": "̄",  # 高调
    "2": "́",  # 升调
    "3": "̌",  # 低调
    "4": "̀",  # 降调
    "5": ""   # 轻声
}

# 标注调号位置优先级顺序
TONE_POSITION_PRIORITY = ['a', 'o', 'e', 'i', 'u', 'ü']


def normalize_special_pinyin(syllabic_quality: str, tone: str) -> str:
    """
    标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）

    参数:
        syllabic_quality: 析出声调的特殊音节的音质
        tone: 声调数字（1-5）

    返回:
        用调号标调的拼音
    """
    if not tone in TONE_MARKS:
        return syllabic_quality

    if syllabic_quality == "ê":
        return "ê" + TONE_MARKS[tone]
    elif syllabic_quality in ["m", "n"]:
        return syllabic_quality + TONE_MARKS[tone]
    elif syllabic_quality == "ng":
        return "n" + TONE_MARKS[tone] + "g"  # 标调在n上
    elif syllabic_quality in ["hm", "hn", "hng"]:
        # 标调在m或n上
        if syllabic_quality == "hng":
            return "h" + "n" + TONE_MARKS[tone] + "g"
        return "h" + syllabic_quality[1] + TONE_MARKS[tone]  # hm → h + m̄, hn → h + ń
    return syllabic_quality


def supplement_special_pinyin(pinyin_dict: Dict[str, str]) -> Dict[str, str]:
    """
    补充缺失的特殊音质拼音并返回新字典

    参数:
        pinyin_dict: 待补充的拼音字典

    返回:
        补充后的新字典
    """
    # 生成所有可能的特殊拼音组合
    special_pinyin_list = [f"{sq}{tone}" for sq in SPECIAL_QUALITIES for tone in TONES]

    # 创建新字典(避免修改原字典)
    supplemented_dict = pinyin_dict.copy()

    # 补充缺失的特殊拼音
    for pinyin in special_pinyin_list:
        if pinyin not in supplemented_dict:
            supplemented_dict[pinyin] = pinyin

    print(f"新增补充的特殊拼音数量: {len(special_pinyin_list) - len(set(pinyin_dict) & set(special_pinyin_list))}")
    return supplemented_dict


def normalize_pinyin(pinyin_with_tone: str) -> str:
    """
    将用数字标调的拼音转换为用调号标调的拼音

    参数:
        pinyin_with_tone: 用数字标调的拼音

    返回:
        用调号标调的拼音
    """
    if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
        return pinyin_with_tone  # 没有调号，直接返回

    tone_num = pinyin_with_tone[-1]
    pinyin = pinyin_with_tone[:-1]

    # 处理v->ü/u转换
    if 'v' in pinyin:
        v_index = pinyin.index('v')
        if v_index > 0:  # 前面有字符
            prev_char = pinyin[v_index-1]
            if prev_char in ['j', 'q', 'x', 'y']:
                pinyin = pinyin.replace('v', 'u')
            elif prev_char in ['l', 'n']:
                pinyin = pinyin.replace('v', 'ü')
        else:  # v在开头
            pinyin = pinyin.replace('v', 'ü')

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


def process_pinyin_dict(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    normalized_dict = {}
    mismatch_count = 0

    # 先补充特殊拼音
    supplemented_dict = supplement_special_pinyin(input_dict)

    # 然后进行标准化
    for key, value in supplemented_dict.items():
        if key != value:
            mismatch_count += 1
            normalized_dict[key] = normalize_pinyin(key)
        else:
            normalized_dict[key] = normalize_pinyin(key)

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
        normalized_dict, mismatch_count = process_pinyin_dict(pinyin_dict)

        # 对字典按键进行排序
        sorted_dict = OrderedDict(sorted(normalized_dict.items(), key=lambda x: x[0]))

        print(f"正在写入输出文件: {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(sorted_dict, f, ensure_ascii=False, indent=2)

        print(f"拼音标准化完成，结果已保存到: {output_file}")
        print(f"共处理 {len(sorted_dict)} 个拼音，其中 {mismatch_count} 个键值不匹配")

    except FileNotFoundError:
        print(f"错误: 输入文件 {input_file} 不存在")
    except json.JSONDecodeError:
        print(f"错误: 输入文件 {input_file} 不是有效的JSON格式")
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")
        raise


if __name__ == "__main__":
    main()