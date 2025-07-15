import json
import os
from collections import defaultdict


def extract_pinyin():
    """
    功能：析取由拼音到汉字的映射字典的拼音

    数据转换流程：
    1. 读取JSON文件，析取键值对象的拼音
    2. 检查不带调的拼音并作记录
    3. 按拼音首字母排序
    4. 构建字典结构：以带调拼音为键和值（键值相同）
    -  输出格式示例：
    {
        "a1": "a1",
        "ba1": "ba1",
        ...,
        "zui4": "zui4"
    }
    5. 将最终字典以JSON格式保存到指定文件
    """
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'pinyin_danzi.json')
    output_file = os.path.join(script_dir, 'pinyin.json')

    # 读取输入JSON文件
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_danzi_dict = json.load(f)
    except FileNotFoundError:
        print(f"错误：输入文件 {input_file} 不存在")
        return
    except json.JSONDecodeError:
        print(f"错误：输入文件 {input_file} 不是有效的JSON格式")
        return

    # 提取拼音并检查
    pinyin_set = set()
    invalid_pinyin = []

    for pinyin in pinyin_danzi_dict.keys():
        # 检查拼音是否带调（末尾有数字1-5）
        if pinyin[-1].isdigit() and 1 <= int(pinyin[-1]) <= 5:
            pinyin_set.add(pinyin)
        else:
            invalid_pinyin.append(pinyin)

    # 记录无效拼音（不带调）
    if invalid_pinyin:
        print(f"发现 {len(invalid_pinyin)} 个不带调的拼音:")
        print(", ".join(invalid_pinyin))

    # 按拼音首字母排序
    sorted_pinyin = sorted(pinyin_set, key=lambda x: x.lower())

    # 构建输出字典
    pinyin_dict = {pinyin: pinyin for pinyin in sorted_pinyin}

    # 保存到输出文件
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(pinyin_dict, f, ensure_ascii=False, indent=2)
        print(f"成功生成拼音字典，已保存到 {output_file}")
    except IOError as e:
        print(f"保存文件时出错: {e}")


if __name__ == "__main__":
    extract_pinyin()
