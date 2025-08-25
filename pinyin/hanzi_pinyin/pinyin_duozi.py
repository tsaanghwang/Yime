import os
import json
from collections import defaultdict


def create_pinyin_to_duozi_mapping():
    """
    创建由拼音到多字词语的映射字典

    数据转换流程：
    1. 读取JSON文件，解析每行带调拼音
    2. 检查不带调的拼音并记录
    3. 构建字典结构：以带调拼音为键，以对应的字形不同的同音多字词语为值
    4. 按拼音首字母排序
    5. 将最终字典以JSON格式保存到指定文件
    """
    # 定义输入输出文件路径 - 使用os.path.join确保跨平台兼容性
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'duozi_pinyin.json')
    output_file = os.path.join(script_dir, 'pinyin_duozi.json')

    # 读取输入JSON文件
    with open(input_file, 'r', encoding='utf-8') as f:
        hanzi_pinyin_dict = json.load(f)

    # 构建拼音到多字词语的映射
    pinyin_duozi_dict = defaultdict(list)

    for hanzi, pinyins in hanzi_pinyin_dict.items():
        for pinyin in pinyins:
            pinyin_duozi_dict[pinyin].append(hanzi)

    # 按拼音首字母排序
    sorted_pinyin_duozi = dict(
        sorted(pinyin_duozi_dict.items(), key=lambda x: x[0]))

    # 保存结果到JSON文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(sorted_pinyin_duozi, f, ensure_ascii=False, indent=4)

    print(f"转换完成，结果已保存到: {output_file}")


if __name__ == "__main__":
    create_pinyin_to_duozi_mapping()
