"""
转换拼音格式
功能：将带数字调号的拼音转换为带声调符号的标准拼音

处理流程：
1. 读取JSON文件，取出每个键值对象（item）的键和值（均为带数字调号的拼音）
2. 判断每个键值对象（item）的键和值是否相同
3. 如果相同，不作处理，保留原值；如果不同，则以该键值对象（item）的键为值，并记录有几个不同
4. 给每个键值对象（item）值（带数字调号的拼音）添加声调符号，亦即将其转换为带声调符号的拼音
5. 添加声调符号的规则参考这个模块当前代码内容：
6. 将分类结果以JSON格式保存到指定文件

输入文件格式：
- JSON字典，格式为 {"pinyin1":"pinyin1", "pinyin2": "pinyin2", ...}
    - 输入格式示例：
    {
        "a1": "a1",
        "ba1": "ba1",
        ...,
        "zui4": "zui4"
    }

输出文件格式：
- JSON字典，格式为 {"带数字调号的拼音1":"标准拼音1", "带数字调号的拼音2": "标准拼音2", ...}
    - 输出格式示例：
    {
        "a1": "ā",
        "ba2": "bá",
        ...,
        "zhuo5": "zhuo"
    }
"""
import json
import os
from pathlib import Path
from typing import Dict, Tuple

# 声调符号映射
TONE_MARKS = {
    "1": "̄",  # 高平调
    "2": "́",  # 升调
    "3": "̌",  # 低平调
    "4": "̀",  # 降调
    "5": ""   # 轻声
}

# 元音优先级顺序
VOWEL_PRIORITY = ['a', 'o', 'e', 'ü', 'i', 'u']


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

    # 按优先级查找元音位置
    for vowel in VOWEL_PRIORITY:
        if vowel in pinyin:
            index = pinyin.index(vowel)
            return pinyin[:index] + vowel + TONE_MARKS[tone_num] + pinyin[index+1:]

    # 没有找到可标调的元音，返回不带调号的拼音
    return pinyin


def process_pinyin_dict(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    """
    处理拼音字典，转换为标准拼音格式

    参数:
        input_dict: 输入拼音字典 {"pinyin1":"pinyin1", ...}

    返回:
        Tuple[标准化后的字典, 不同键值对的数量]
    """
    normalized_dict = {}
    mismatch_count = 0

    for key, value in input_dict.items():
        if key != value:
            mismatch_count += 1
            # 使用键作为标准值
            normalized_dict[key] = normalize_pinyin(key)
        else:
            normalized_dict[key] = normalize_pinyin(value)

    return normalized_dict, mismatch_count


def main():
    """主处理函数"""
    # 定义输入输出文件路径
    script_dir = Path(__file__).parent.absolute()
    input_file = script_dir / "pinyin.json"
    output_file = script_dir / "pinyin_normalized.json"

    try:
        # 读取输入文件
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        # 处理拼音字典
        normalized_dict, mismatch_count = process_pinyin_dict(pinyin_dict)

        # 写入输出文件
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(normalized_dict, f, ensure_ascii=False, indent=2)

        print(f"拼音标准化完成，结果已保存到: {output_file}")
        if mismatch_count > 0:
            print(f"发现 {mismatch_count} 个键值不匹配的拼音")

    except FileNotFoundError:
        print(f"错误: 输入文件 {input_file} 不存在")
    except json.JSONDecodeError:
        print(f"错误: 输入文件 {input_file} 不是有效的JSON格式")
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")


if __name__ == "__main__":
    main()
