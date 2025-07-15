"""
单字YAML到JSON转换器
功能：
1. 将YAML文件中的汉字-拼音对转换为JSON格式
2. 处理重复汉字的情况，合并拼音列表
3. 输入格式：
    㚡\tji3
    㚢\tnu2
    㚢\twu3
4. 输出格式：
{
    "汉字": ["拼音1", "拼音2", ...],
}
"""

import yaml
import json
import os
from collections import defaultdict
from pathlib import Path

# 定义绝对路径
SCRIPT_DIR = Path(__file__).parent
INPUT_FILE = SCRIPT_DIR / "hanzi_pinyin_danzi.yaml"
OUTPUT_FILE = SCRIPT_DIR / "danzi_pinyin.json"


def merge_duplicate_keys(yaml_data):
    """
    合并YAML数据中的重复键(单字)

    Args:
        yaml_data: 原始YAML数据

    Returns:
        合并后的字典数据
    """
    merged = defaultdict(list)
    duplicate_count = 0  # 多音字计数器

    for hanzi, pinyin in yaml_data:
        # 如果汉字已存在且拼音不在列表中，则增加多音字计数
        if hanzi in merged and pinyin not in merged[hanzi]:
            duplicate_count += 1
        # 只添加不重复的拼音
        if pinyin not in merged[hanzi]:
            merged[hanzi].append(pinyin)

    return dict(merged), duplicate_count


def convert_yaml_to_json(input_path, output_path):
    """
    主转换流程

    Args:
        input_path: 输入YAML文件路径
        output_path: 输出JSON文件路径
    """
    try:
        with open(input_path, "r", encoding="utf-8") as f:
            # 读取每行并分割汉字和拼音
            lines = [line.strip().split("\t") for line in f if line.strip()]
            yaml_data = [(hanzi, pinyin) for hanzi, pinyin in lines]
            original_count = len(yaml_data)  # 原始YAML行数

        merged_data, duplicate_count = merge_duplicate_keys(yaml_data)
        merged_count = len(merged_data)  # 合并后的汉字数量

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(merged_data, f, ensure_ascii=False, indent=2)

        # 打印统计信息
        print(f"转换统计:")
        print(f"- 原始YAML行数: {original_count}")
        print(f"- 合并后汉字数量: {merged_count}")
        print(f"- 多音字数量(需要合并的行): {duplicate_count}")
        print(f"JSON文件已保存到: {output_path}")
        return True
    except Exception as e:
        print(f"转换过程中发生错误: {str(e)}")
        return False


if __name__ == "__main__":
    # 直接使用预定义的路径运行
    if not INPUT_FILE.exists():
        print(f"错误：输入文件 {INPUT_FILE} 不存在")
    else:
        convert_yaml_to_json(str(INPUT_FILE), str(OUTPUT_FILE))
